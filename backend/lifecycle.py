from datetime import timedelta
from time import sleep

import click
import pymysql
from flask import current_app
from flask.cli import with_appcontext

from audit import record_event
from database import get_db, utc_iso
from sla import (
    finish_milestone, load_calendar, lock_calendar, now_utc, open_milestones,
    record_breach, record_overdue, set_deadline, start_cycle, working_microseconds,
)


ACTIVE_STATUSES = ("open", "waiting_on_customer")
CLOSED_STATUSES = ("resolved", "closed_inactivity")
WAIT_DURATION = timedelta(hours=45)
REOPEN_DURATION = timedelta(days=7)
LOCK_FIELDS = "id, customer_id, owner_id, ownership_version, status, priority, waiting_since, waiting_until, waiting_message_id, closed_at"


def log(connection, ticket_id, action, actor_id, at, **details):
    record_event(connection, action, actor_id=actor_id, entity_type="ticket", entity_id=ticket_id,
                 occurred_at=at, details=details)


def lock_ticket(connection, ticket_id):
    with connection.cursor() as cursor:
        cursor.execute(f"SELECT {LOCK_FIELDS} FROM tickets WHERE id = %s FOR UPDATE", (ticket_id,))
        return cursor.fetchone()


def latest_cycle(connection, ticket_id):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT id, cycle_number, started_at FROM ticket_sla_cycles WHERE ticket_id = %s ORDER BY cycle_number DESC LIMIT 1 FOR UPDATE",
            (ticket_id,),
        )
        return cursor.fetchone()


def qualifying_reply(connection, ticket):
    cycle = latest_cycle(connection, ticket["id"])
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT completed_at FROM ticket_sla_milestones WHERE cycle_id = %s AND milestone = 'first_response' LOCK IN SHARE MODE",
            (cycle["id"],),
        )
        if cursor.fetchone()["completed_at"] is None:
            return None
        cursor.execute(
            """
            SELECT id, author_id FROM ticket_messages
            WHERE ticket_id = %s AND visibility = 'public' AND created_at >= %s
            ORDER BY id DESC LIMIT 1 LOCK IN SHARE MODE
            """,
            (ticket["id"], cycle["started_at"]),
        )
        message = cursor.fetchone()
    if message and message["author_id"] != ticket["customer_id"]:
        return message["id"]
    return None


def mark_waiting(connection, ticket, actor_id, message_id, at, calendar):
    until = calendar.add_working_time(at, WAIT_DURATION)
    with connection.cursor() as cursor:
        for milestone in open_milestones(connection, "c.ticket_id = %s", (ticket["id"],)):
            record_breach(connection, milestone, at)
            if milestone["breached_at"] is None:
                remaining = calendar.working_time_between(at, milestone["deadline_at"])
                cursor.execute(
                    "UPDATE ticket_sla_milestones SET paused_work_us = %s WHERE cycle_id = %s AND milestone = %s",
                    (working_microseconds(remaining), milestone["cycle_id"], milestone["milestone"]),
                )
        cursor.execute(
            """
            UPDATE tickets SET status = 'waiting_on_customer', waiting_since = %s,
                waiting_until = %s, waiting_message_id = %s WHERE id = %s
            """,
            (at, until, message_id, ticket["id"]),
        )
    log(connection, ticket["id"], "sla_paused", actor_id, at, message_id=message_id, inactivity_deadline=utc_iso(until))


def resume_wait(connection, ticket, actor_id, at, calendar, *, reason, message_id=None):
    changes = {}
    with connection.cursor() as cursor:
        for milestone in open_milestones(connection, "c.ticket_id = %s AND m.paused_work_us IS NOT NULL", (ticket["id"],)):
            old = milestone["deadline_at"]
            deadline = calendar.add_working_time(at, timedelta(microseconds=milestone["paused_work_us"]))
            # A pause outside office hours adds zero working time to the promise.
            if not calendar.working_time_between(ticket["waiting_since"], at) and old >= at:
                if calendar.working_time_between(at, old) == timedelta(microseconds=milestone["paused_work_us"]):
                    deadline = old
            kind = milestone["deadline_kind"] if deadline == old else "working_time"
            set_deadline(connection, milestone, deadline, kind)
            cursor.execute(
                "UPDATE ticket_sla_milestones SET paused_work_us = NULL WHERE cycle_id = %s AND milestone = %s",
                (milestone["cycle_id"], milestone["milestone"]),
            )
            changes[milestone["milestone"]] = {"old_deadline": utc_iso(old), "new_deadline": utc_iso(deadline)}
        cursor.execute(
            "UPDATE tickets SET status = 'open', waiting_since = NULL, waiting_until = NULL, waiting_message_id = NULL WHERE id = %s",
            (ticket["id"],),
        )
    log(connection, ticket["id"], "sla_resumed", actor_id, at, reason=reason, message_id=message_id,
        waiting_since=utc_iso(ticket["waiting_since"]), deadlines=changes)


def close_cycle(connection, ticket, actor_id, status, at):
    cycle = latest_cycle(connection, ticket["id"])
    for milestone in open_milestones(connection, "c.ticket_id = %s", (ticket["id"],)):
        finish_milestone(
            connection, milestone, actor_id, at,
            completed=status == "resolved" and milestone["milestone"] == "resolution",
            check_breach=status == "resolved",
        )
    with connection.cursor() as cursor:
        cursor.execute("UPDATE ticket_sla_cycles SET ended_at = %s, closure_status = %s WHERE id = %s", (at, status, cycle["id"]))
        cursor.execute(
            """
            UPDATE tickets SET status = %s, closed_at = %s, waiting_since = NULL,
                waiting_until = NULL, waiting_message_id = NULL WHERE id = %s
            """,
            (status, at, ticket["id"]),
        )
    details = {"cycle_number": cycle["cycle_number"]}
    if status == "closed_inactivity":
        details.update(reason="no_customer_reply_for_45_working_hours", waiting_since=utc_iso(ticket["waiting_since"]))
    log(connection, ticket["id"], "ticket_resolved" if status == "resolved" else "ticket_closed_inactivity", actor_id, at, **details)
    ticket.update(status=status, closed_at=at, waiting_since=None, waiting_until=None, waiting_message_id=None)


def expire_wait(connection, ticket, at):
    if ticket["status"] != "waiting_on_customer" or ticket["waiting_until"] is None or at < ticket["waiting_until"]:
        return False
    close_cycle(connection, ticket, None, "closed_inactivity", ticket["waiting_until"])
    return True


def reopen_until(ticket):
    if ticket["status"] in CLOSED_STATUSES and ticket["closed_at"] is not None:
        return ticket["closed_at"] + REOPEN_DURATION
    return None


def reopen_ticket(connection, ticket, actor_id, at, calendar):
    previous = latest_cycle(connection, ticket["id"])
    previous_owner = ticket["owner_id"]
    new_owner = previous_owner
    with connection.cursor() as cursor:
        if previous_owner is not None:
            cursor.execute("SELECT id FROM accounts WHERE id = %s AND is_active LOCK IN SHARE MODE", (previous_owner,))
            if cursor.fetchone() is None:
                new_owner = None
        cursor.execute(
            "UPDATE tickets SET status = 'open', closed_at = NULL, owner_id = %s, ownership_version = ownership_version + 1 WHERE id = %s",
            (new_owner, ticket["id"]),
        )
    number = previous["cycle_number"] + 1
    deadlines = start_cycle(connection, ticket["id"], ticket["priority"], at, calendar, number=number)
    log(connection, ticket["id"], "ticket_reopened", actor_id, at, previous_closure=ticket["status"],
        previous_cycle=previous["cycle_number"], cycle_number=number, deadlines=deadlines,
        from_owner_id=previous_owner, to_owner_id=new_owner)
    ticket.update(status="open", closed_at=None, owner_id=new_owner)


def expire_due_tickets(connection, at):
    with connection.cursor() as cursor:
        cursor.execute(
            f"SELECT {LOCK_FIELDS} FROM tickets WHERE status = 'waiting_on_customer' AND waiting_until <= %s ORDER BY id FOR UPDATE",
            (at,),
        )
        rows = cursor.fetchall()
    return sum(expire_wait(connection, ticket, at) for ticket in rows)


def reflow_waiting(connection, old_calendar, new_calendar, at, event_id, actor_id):
    moved = 0
    with connection.cursor() as cursor:
        cursor.execute("SELECT id, waiting_until FROM tickets WHERE status = 'waiting_on_customer' AND waiting_until > %s ORDER BY id FOR UPDATE", (at,))
        rows = cursor.fetchall()
        for ticket in rows:
            old = ticket["waiting_until"]
            new = new_calendar.add_working_time(at, old_calendar.working_time_between(at, old))
            if new != old:
                cursor.execute("UPDATE tickets SET waiting_until = %s WHERE id = %s", (new, ticket["id"]))
                log(connection, ticket["id"], "ticket_inactivity_deadline_changed", actor_id, at,
                    old_deadline=utc_iso(old), new_deadline=utc_iso(new), holiday_event_id=event_id)
                moved += 1
    return moved


@click.command("ticket-lifecycle")
@click.option("--watch", is_flag=True, help="Keep checking for closures and SLA breaches.")
@click.option("--interval", default=30, type=click.IntRange(min=1), show_default=True)
@with_appcontext
def ticket_lifecycle(watch, interval):
    if watch:
        click.echo(f"Checking tickets every {interval} seconds.")
    while True:
        try:
            with current_app.app_context():
                connection = get_db()
                lock_calendar(connection, editing=True)
                at = now_utc()
                closed = expire_due_tickets(connection, at)
                breached = record_overdue(connection, at)
                connection.commit()
            if closed or breached or not watch:
                click.echo(f"Closed {closed} inactive ticket(s). Recorded {breached} new SLA breach(es).")
        except pymysql.MySQLError as error:
            if not watch:
                raise
            click.echo(f"Ticket check failed and will retry: {error.args[0]}", err=True)
        if not watch:
            return
        sleep(interval)
