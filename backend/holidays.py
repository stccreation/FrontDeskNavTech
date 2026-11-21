from datetime import date

from flask import Blueprint, jsonify

from audit import record_event
from auth import MANAGEMENT_ROLES, current_account, error_response, json_object, require_roles
from business_hours import BusinessCalendar, HolidayEvent, local_date
from database import get_db
from lifecycle import expire_due_tickets, reflow_waiting
from sla import load_calendar, lock_calendar, now_utc, reflow_after_holiday


holidays = Blueprint("holidays", __name__, url_prefix="/api/holidays")


def parse_date(value):
    if not isinstance(value, str):
        return None
    try:
        day = date.fromisoformat(value)
        return day if day.isoformat() == value else None
    except ValueError:
        return None


@holidays.get("")
@require_roles(*MANAGEMENT_ROLES)
def list_holidays():
    calendar = load_calendar(get_db())
    return jsonify(
        today=local_date(now_utc()).isoformat(),
        holidays=[{"date": day.isoformat(), "name": name} for day, name in sorted(calendar.active_holidays().items())],
    )


def edit_holiday(day, name=None):
    if day is None:
        return error_response("Enter a holiday date in YYYY-MM-DD format.", 400)
    connection = get_db()
    lock_calendar(connection, editing=True)
    at = now_utc()
    if day < local_date(at):
        return error_response("Choose today or a future date. Past holiday dates are kept for history.", 400)

    previous = load_calendar(connection, locked=True)
    existing_name = previous.active_holidays().get(day)
    adding = name is not None
    if adding and existing_name is not None:
        return error_response("This date already has a holiday.", 409)
    if not adding and existing_name is None:
        return error_response("Holiday not found.", 404)
    event = HolidayEvent(day, name if adding else existing_name, adding, at)
    with connection.cursor() as cursor:
        cursor.execute(
            "INSERT INTO holiday_events (holiday_date, name, is_holiday, effective_at) VALUES (%s, %s, %s, %s)",
            (event.day, event.name, event.active, event.effective_at),
        )
        holiday_event_id = cursor.lastrowid
    actor_id = current_account()["id"]
    record_event(
        connection, "holiday_added" if adding else "holiday_removed", actor_id=actor_id,
        entity_type="holiday", entity_id=holiday_event_id, occurred_at=at,
        details={"date": day.isoformat(), "name": event.name},
    )
    updated = BusinessCalendar((*previous.events, event))
    expire_due_tickets(connection, at)
    changed = reflow_after_holiday(connection, previous, updated, at, holiday_event_id, actor_id)
    changed += reflow_waiting(connection, previous, updated, at, holiday_event_id, actor_id)
    connection.commit()
    return jsonify(date=day.isoformat(), deadlines_updated=changed), 201 if adding else 200


@holidays.post("")
@require_roles(*MANAGEMENT_ROLES)
def add_holiday():
    payload = json_object()
    name = payload.get("name")
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 120:
        return error_response("Enter a holiday name up to 120 characters.", 400)
    return edit_holiday(parse_date(payload.get("date")), name.strip())


@holidays.post("/<day>/remove")
@require_roles(*MANAGEMENT_ROLES)
def remove_holiday(day):
    return edit_holiday(parse_date(day))
