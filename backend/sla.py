from datetime import UTC, datetime, timedelta

import click
from flask import current_app
from flask.cli import with_appcontext

from audit import record_event
from business_hours import BusinessCalendar, HolidayEvent
from database import get_db, utc_iso


PRIORITY_ORDER = {"low": 0, "medium": 1, "urgent": 2}
WORKING_HOURS = {"urgent": (2, None), "medium": (4.5, 27), "low": (9, 45)}
MILESTONES = ("first_response", "resolution")


def now_utc():
    clock = current_app.config.get("SLA_CLOCK")
    return clock() if clock is not None else datetime.now(UTC).replace(tzinfo=None)


def lock_calendar(connection, *, editing=False):
    lock = "FOR UPDATE" if editing else "LOCK IN SHARE MODE"
    with connection.cursor() as cursor:
        cursor.execute(f"SELECT id FROM sla_calendar_lock WHERE id = 1 {lock}")
        if cursor.fetchone() is None:
            raise RuntimeError("Apply the SLA calendar migration before running Frontdesk.")


def load_calendar(connection, *, locked=False):
    lock = "LOCK IN SHARE MODE" if locked else ""
    with connection.cursor() as cursor:
        cursor.execute(
            f"SELECT holiday_date, name, is_holiday, effective_at FROM holiday_events ORDER BY effective_at, id {lock}"
        )
        return BusinessCalendar(
            HolidayEvent(row["holiday_date"], row["name"], bool(row["is_holiday"]), row["effective_at"])
            for row in cursor.fetchall()
        )


def proposed_deadlines(calendar, priority, start):
    reply_hours, resolution_hours = WORKING_HOURS[priority]
    reply = calendar.add_working_time(start, timedelta(hours=reply_hours))
    if resolution_hours is None:
        resolution = (calendar.working_day_close(start), "day_end")
    else:
        resolution = (calendar.add_working_time(start, timedelta(hours=resolution_hours)), "working_time")
    return {"first_response": (reply, "working_time"), "resolution": resolution}


def start_cycle(connection, ticket_id, priority, started_at, calendar, *, number=1):
    deadlines = proposed_deadlines(calendar, priority, started_at)
    with connection.cursor() as cursor:
        cursor.execute(
            "INSERT INTO ticket_sla_cycles (ticket_id, cycle_number, started_at) VALUES (%s, %s, %s)",
            (ticket_id, number, started_at),
        )
        cycle_id = cursor.lastrowid
        cursor.executemany(
            """
            INSERT INTO ticket_sla_milestones (cycle_id, milestone, deadline_at, deadline_kind)
            VALUES (%s, %s, %s, %s)
            """,
            [(cycle_id, milestone, *deadline) for milestone, deadline in deadlines.items()],
        )
    return {milestone: utc_iso(deadline[0]) for milestone, deadline in deadlines.items()}


def open_milestones(connection, condition, arguments=()):
    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            SELECT m.*, c.ticket_id, c.cycle_number, t.status
            FROM ticket_sla_milestones m JOIN ticket_sla_cycles c ON c.id = m.cycle_id
            JOIN tickets t ON t.id = c.ticket_id
            WHERE c.ended_at IS NULL AND m.result IS NULL AND {condition}
            ORDER BY c.ticket_id, m.milestone FOR UPDATE
            """,
            arguments,
        )
        return cursor.fetchall()


def record_breach(connection, milestone, observed_at):
    if milestone["breached_at"] is not None or observed_at <= milestone["deadline_at"]:
        return False
    boundary = milestone["deadline_at"]
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE ticket_sla_milestones SET breached_at = %s WHERE cycle_id = %s AND milestone = %s",
            (boundary, milestone["cycle_id"], milestone["milestone"]),
        )
    milestone["breached_at"] = boundary
    record_event(
        connection, "sla_deadline_missed", actor_id=None, entity_type="ticket", entity_id=milestone["ticket_id"],
        occurred_at=boundary,
        details={
            "cycle_number": milestone["cycle_number"], "milestone": milestone["milestone"],
            "deadline": utc_iso(boundary), "observed_at": utc_iso(observed_at),
        },
    )
    return True


def record_overdue(connection, at):
    rows = open_milestones(connection, "t.status = 'open' AND m.breached_at IS NULL AND m.deadline_at < %s", (at,))
    return sum(record_breach(connection, milestone, at) for milestone in rows)


def complete_first_response(connection, ticket_id, actor_id, at):
    rows = open_milestones(connection, "c.ticket_id = %s AND m.milestone = 'first_response'", (ticket_id,))
    if rows:
        finish_milestone(connection, rows[0], actor_id, at, completed=True)


def finish_milestone(connection, milestone, actor_id, at, *, completed, check_breach=True):
    if check_breach:
        record_breach(connection, milestone, at)
    result = "late" if milestone["breached_at"] is not None else ("met" if completed else "not_applicable")
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE ticket_sla_milestones SET completed_at = %s, result = %s, paused_work_us = NULL WHERE cycle_id = %s AND milestone = %s",
            (at if completed else None, result, milestone["cycle_id"], milestone["milestone"]),
        )
    record_event(
        connection, "sla_milestone_completed" if completed else "sla_milestone_closed",
        actor_id=actor_id, entity_type="ticket", entity_id=milestone["ticket_id"],
        occurred_at=at,
        details={
            "cycle_number": milestone["cycle_number"], "milestone": milestone["milestone"],
            "deadline": utc_iso(milestone["deadline_at"]), "completed_at": utc_iso(at) if completed else None,
            "result": result,
        },
    )


def working_microseconds(duration):
    return duration // timedelta(microseconds=1)


def set_deadline(connection, milestone, deadline, kind):
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE ticket_sla_milestones SET deadline_at = %s, deadline_kind = %s WHERE cycle_id = %s AND milestone = %s",
            (deadline, kind, milestone["cycle_id"], milestone["milestone"]),
        )


def apply_priority(connection, ticket_id, old_priority, priority, at, calendar):
    proposals = proposed_deadlines(calendar, priority, at)
    upgrading = PRIORITY_ORDER[priority] > PRIORITY_ORDER[old_priority]
    changes = {}
    for milestone in open_milestones(connection, "c.ticket_id = %s", (ticket_id,)):
        name = milestone["milestone"]
        paused = milestone["paused_work_us"]
        old = milestone["deadline_at"] if paused is None else calendar.add_working_time(at, timedelta(microseconds=paused))
        proposed, kind = proposals[name]
        if paused is None:
            record_breach(connection, milestone, at)
        new = old
        if milestone["breached_at"] is not None:
            rule = "kept_recorded_breach"
        elif upgrading and proposed < old:
            new = proposed
            set_deadline(connection, milestone, new, kind)
            if paused is not None:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "UPDATE ticket_sla_milestones SET paused_work_us = %s WHERE cycle_id = %s AND milestone = %s",
                        (working_microseconds(calendar.working_time_between(at, new)), milestone["cycle_id"], name),
                    )
            rule = f"tightened_to_{priority}"
        else:
            rule = "kept_original" if upgrading else "downgrade_kept_promised_deadline"
        changes[name] = {
            "old_deadline": utc_iso(old), "new_deadline": utc_iso(new),
            "normal_deadline": utc_iso(proposed), "rule": rule,
        }
    return changes


def reflow_after_holiday(connection, old_calendar, new_calendar, at, holiday_event_id, actor_id):
    record_overdue(connection, at)
    moved = 0
    rows = open_milestones(connection, "t.status = 'open' AND m.breached_at IS NULL AND m.deadline_at > %s", (at,))
    for milestone in rows:
        old = milestone["deadline_at"]
        kind = milestone["deadline_kind"]
        if kind == "day_end":
            new = new_calendar.working_day_close(at)
        else:
            remaining = old_calendar.working_time_between(at, old)
            new = new_calendar.add_working_time(at, remaining)
        if new == old:
            continue
        set_deadline(connection, milestone, new, kind)
        record_event(
            connection, "sla_deadline_changed", actor_id=actor_id, entity_type="ticket",
            entity_id=milestone["ticket_id"], occurred_at=at,
            details={
                "cycle_number": milestone["cycle_number"], "milestone": milestone["milestone"],
                "old_deadline": utc_iso(old), "new_deadline": utc_iso(new), "reason": "holiday_calendar_changed",
                "holiday_event_id": holiday_event_id,
            },
        )
        moved += 1
    return moved


def ticket_slas(connection, tickets, at, *, include_history=False):
    if not tickets:
        return {}
    statuses = {ticket["id"]: ticket["status"] for ticket in tickets}
    placeholders = ", ".join(["%s"] * len(statuses))
    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            SELECT c.ticket_id, c.cycle_number, c.started_at, c.ended_at, c.closure_status, m.milestone, m.deadline_at,
                   m.completed_at, m.breached_at, m.result, m.paused_work_us
            FROM ticket_sla_cycles c JOIN ticket_sla_milestones m ON m.cycle_id = c.id
            WHERE c.ticket_id IN ({placeholders})
            ORDER BY c.ticket_id, c.cycle_number DESC
            """,
            tuple(statuses),
        )
        rows = cursor.fetchall()

    cycles = {}
    for row in rows:
        ticket_id = row["ticket_id"]
        number = row["cycle_number"]
        sla = cycles.setdefault(ticket_id, {}).setdefault(number, {
            "cycle_number": number,
            "started_at": utc_iso(row["started_at"]),
            "closure_status": row["closure_status"],
            "closed_at": utc_iso(row["ended_at"]) if row["ended_at"] else None,
        })
        overdue = row["result"] is None and (
            row["breached_at"] is not None or statuses[ticket_id] == "open" and row["deadline_at"] < at
        )
        sla[row["milestone"]] = {
            "deadline": utc_iso(row["deadline_at"]),
            "completed_at": utc_iso(row["completed_at"]) if row["completed_at"] else None,
            "status": row["result"] or ("overdue" if overdue else "paused" if row["paused_work_us"] is not None else "pending"),
        }
    result = {}
    for ticket_id, history in cycles.items():
        current, *previous = history.values()
        if include_history:
            current["previous_cycles"] = previous
        result[ticket_id] = current
    return result


@click.command("sla-backfill")
@with_appcontext
def sla_backfill():
    connection = get_db()
    lock_calendar(connection, editing=True)
    calendar = load_calendar(connection, locked=True)
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT t.id, t.priority, t.created_at FROM tickets t LEFT JOIN ticket_sla_cycles c ON c.ticket_id = t.id
            WHERE c.id IS NULL ORDER BY t.id FOR UPDATE
            """
        )
        tickets = cursor.fetchall()
        for ticket in tickets:
            ticket_id = ticket["id"]
            start_cycle(connection, ticket_id, ticket["priority"], ticket["created_at"], calendar)
            cursor.execute(
                """
                SELECT m.author_id, m.created_at FROM ticket_messages m JOIN accounts a ON a.id = m.author_id
                WHERE m.ticket_id = %s AND m.visibility = 'public' AND a.role <> 'customer'
                ORDER BY m.created_at, m.id LIMIT 1
                """,
                (ticket_id,),
            )
            first = cursor.fetchone()
            if first:
                complete_first_response(connection, ticket_id, first["author_id"], first["created_at"])
    connection.commit()
    click.echo(f"Initialized SLA timing for {len(tickets)} existing ticket(s).")


@click.command("sla-check")
@with_appcontext
def sla_check():
    connection = get_db()
    lock_calendar(connection, editing=True)
    count = record_overdue(connection, now_utc())
    connection.commit()
    click.echo(f"Recorded {count} new SLA breach(es).")
