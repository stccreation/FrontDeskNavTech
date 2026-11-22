import json
from datetime import time

from flask import Blueprint, jsonify, request

from auth import MANAGEMENT_ROLES, error_response, require_roles
from business_hours import DAY, local_date, utc_boundary
from database import get_db, utc_iso
from holidays import parse_date
from notifications import STATUSES, delivery_settings
from sla import now_utc


reports = Blueprint("reports", __name__, url_prefix="/api/reports")
PAGE_SIZE = 40
MISS_SOURCE = """
    SELECT t.id AS ticket_id, t.subject, c.id AS cycle_id, c.cycle_number, c.closure_status,
           m.milestone, m.deadline_at, m.completed_at, COALESCE(m.breached_at, m.deadline_at) AS missed_at
    FROM ticket_sla_milestones m JOIN ticket_sla_cycles c ON c.id = m.cycle_id
    JOIN tickets t ON t.id = c.ticket_id
    WHERE COALESCE(m.breached_at, m.deadline_at) >= %s AND COALESCE(m.breached_at, m.deadline_at) < %s
      AND (m.breached_at IS NOT NULL OR (m.result IS NULL AND m.paused_work_us IS NULL
           AND c.ended_at IS NULL AND t.status = 'open' AND m.deadline_at < %s))
"""


@reports.get("/sla")
@require_roles(*MANAGEMENT_ROLES)
def sla_report():
    now = now_utc()
    today = local_date(now)
    first = parse_date(request.args["from"]) if "from" in request.args else today.replace(day=1)
    last = parse_date(request.args["to"]) if "to" in request.args else today
    if first is None or last is None or first > last or last > today or (last - first).days >= 366:
        return error_response("Choose a report period of up to 366 days ending today or earlier.", 400)
    offset = request.args.get("offset", type=int) if "offset" in request.args else 0
    milestone = request.args.get("milestone", "all")
    if offset is None or not 0 <= offset <= 1000000 or milestone not in ("all", "first_response", "resolution"):
        return error_response("Choose a valid report page and milestone.", 400)

    start = utc_boundary(first, time.min)
    end = utc_boundary(last + DAY, time.min)
    params = (start, end, now)
    misses = {"first_response": 0, "resolution": 0}
    closures = {key: {"count": 0, "reopened": 0} for key in ("resolved", "closed_inactivity")}
    notifications = dict.fromkeys(STATUSES, 0)
    with get_db().cursor() as cursor:
        cursor.execute(f"SELECT milestone, COUNT(*) AS count FROM ({MISS_SOURCE}) missed GROUP BY milestone", params)
        for row in cursor.fetchall():
            misses[row["milestone"]] = row["count"]

        condition = "" if milestone == "all" else "WHERE milestone = %s"
        arguments = params if milestone == "all" else (*params, milestone)
        cursor.execute(
            f"""
            SELECT * FROM ({MISS_SOURCE}) missed {condition}
            ORDER BY missed_at DESC, cycle_id DESC, milestone LIMIT %s OFFSET %s
            """,
            (*arguments, PAGE_SIZE + 1, offset),
        )
        rows = list(cursor.fetchall())

        # Bucket by days from local midnight at the start of the report.
        span = (last - first).days + 1
        interval = 1 if span <= 14 else 7 if span <= 98 else 28
        activity = [
            {
                "from": (first + index * DAY).isoformat(),
                "to": min(first + (index + interval - 1) * DAY, last).isoformat(),
                "resolved": 0,
                "closed_inactivity": 0,
            }
            for index in range(0, span, interval)
        ]
        cursor.execute(
            """
            SELECT TIMESTAMPDIFF(DAY, %s, closed.ended_at) DIV %s AS bucket,
                   closed.closure_status, COUNT(*) AS count, SUM(reopened.id IS NOT NULL) AS reopened
            FROM ticket_sla_cycles closed LEFT JOIN ticket_sla_cycles reopened
              ON reopened.ticket_id = closed.ticket_id AND reopened.cycle_number = closed.cycle_number + 1
            WHERE closed.ended_at >= %s AND closed.ended_at < %s AND closed.closure_status IS NOT NULL
            GROUP BY bucket, closed.closure_status
            """,
            (start, interval, start, end),
        )
        for row in cursor.fetchall():
            status = row["closure_status"]
            activity[row["bucket"]][status] = row["count"]
            closures[status]["count"] += row["count"]
            closures[status]["reopened"] += int(row["reopened"])

        cursor.execute(
            """
            SELECT actor.id AS staff_id, actor.name, COUNT(*) AS resolved,
                   COUNT(CASE WHEN m.result = 'met' THEN 1 END) AS on_time
            FROM ticket_sla_cycles c JOIN audit_events e
              ON e.entity_type = 'ticket' AND e.entity_id = c.ticket_id
              AND e.action = 'ticket_resolved' AND e.occurred_at = c.ended_at
              AND CAST(JSON_UNQUOTE(JSON_EXTRACT(e.details, '$.cycle_number')) AS UNSIGNED) = c.cycle_number
            JOIN accounts actor ON actor.id = e.actor_account_id
            JOIN ticket_sla_milestones m ON m.cycle_id = c.id AND m.milestone = 'resolution'
            WHERE c.closure_status = 'resolved' AND c.ended_at >= %s AND c.ended_at < %s
            GROUP BY actor.id, actor.name
            ORDER BY resolved DESC, actor.name, actor.id
            """,
            (start, end),
        )
        leaderboard = cursor.fetchall()

        cursor.execute("SELECT status, COUNT(*) AS count FROM reply_notifications WHERE queued_at >= %s AND queued_at < %s GROUP BY status", (start, end))
        for row in cursor.fetchall():
            notifications[row["status"]] = row["count"]

    visible = rows[:PAGE_SIZE]
    for row in visible:
        row.pop("cycle_id")
        for field in ("deadline_at", "completed_at", "missed_at"):
            row[field] = utc_iso(row[field]) if row[field] is not None else None
    return jsonify(
        period={"from": first.isoformat(), "to": last.isoformat(), "today": today.isoformat()},
        misses=misses, closures=closures,
        closure_activity={"interval_days": interval, "buckets": activity},
        leaderboard=leaderboard,
        notifications=notifications | {"delivery_configured": delivery_settings() is not None},
        tickets=visible,
        next_offset=offset + PAGE_SIZE if len(rows) > PAGE_SIZE else None,
    )


@reports.get("/tickets/<int:ticket_id>/history")
@require_roles(*MANAGEMENT_ROLES)
def ticket_history(ticket_id):
    before = request.args.get("before", type=int)
    if "before" in request.args and (before is None or before <= 0):
        return error_response("Choose a valid history page.", 400)
    limit = 75
    with get_db().cursor() as cursor:
        cursor.execute("SELECT id FROM tickets WHERE id = %s", (ticket_id,))
        if cursor.fetchone() is None:
            return error_response("Ticket not found.", 404)
        before_clause = "AND e.id < %s" if before is not None else ""
        params = (ticket_id, before, limit + 1) if before is not None else (ticket_id, limit + 1)
        cursor.execute(
            f"""
            SELECT e.id, e.occurred_at, e.action, e.details, actor.name AS actor_name
            FROM audit_events e LEFT JOIN accounts actor ON actor.id = e.actor_account_id
            WHERE e.entity_type = 'ticket' AND e.entity_id = %s {before_clause}
            ORDER BY e.id DESC LIMIT %s
            """,
            params,
        )
        rows = cursor.fetchall()
    events = rows[:limit]
    for event in events:
        event["occurred_at"] = utc_iso(event["occurred_at"])
        event["details"] = json.loads(event["details"])
    return jsonify(events=events, next_before=events[-1]["id"] if len(rows) > limit else None)
