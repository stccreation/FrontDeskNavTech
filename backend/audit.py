import json

from database import utc_iso


def record_event(connection, action, *, actor_id, entity_type, entity_id, details=None, occurred_at=None):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO audit_events (occurred_at, actor_account_id, action, entity_type, entity_id, details)
            VALUES (COALESCE(%s, UTC_TIMESTAMP(6)), %s, %s, %s, %s, %s)
            """,
            (occurred_at, actor_id, action, entity_type, entity_id, json.dumps(details or {})),
        )


def recent_events(connection):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT id, occurred_at, actor_account_id, action, entity_type, entity_id, details
            FROM audit_events ORDER BY id DESC LIMIT 100
            """
        )
        events = cursor.fetchall()

    for event in events:
        event["occurred_at"] = utc_iso(event["occurred_at"])
        event["details"] = json.loads(event["details"])
    return events
