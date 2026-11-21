from collections import defaultdict

from flask import Blueprint, current_app, jsonify, request, send_from_directory

from attachments import message_submission, stage_attachments
from audit import record_event
from auth import MANAGEMENT_ROLES, STAFF_ROLES, current_account, error_response, json_object, require_roles
from database import get_db, utc_iso
from lifecycle import (
    ACTIVE_STATUSES, CLOSED_STATUSES, close_cycle, expire_wait, lock_ticket, mark_waiting,
    qualifying_reply, reopen_ticket, reopen_until, resume_wait,
)
from notifications import queue_reply
from sla import (
    PRIORITY_ORDER, apply_priority, complete_first_response, load_calendar, lock_calendar,
    now_utc, start_cycle, ticket_slas,
)


tickets = Blueprint("tickets", __name__, url_prefix="/api/tickets")
PAGE_SIZE = 50
MESSAGE_LENGTH = 8000
TICKET_COLUMNS = """
    t.id, t.subject, t.priority, t.customer_blocked, t.status, t.created_at,
    t.customer_id, customer.name AS customer_name, t.owner_id, t.ownership_version,
    owner.name AS owner_name, t.closed_at, t.waiting_until
"""
TICKET_FROM = """
    FROM tickets t JOIN accounts customer ON customer.id = t.customer_id
    LEFT JOIN accounts owner ON owner.id = t.owner_id
"""
STATUS_FILTERS = {
    "open": "t.status = 'open'",
    "waiting": "t.status = 'waiting_on_customer'",
    "closed": "t.status IN ('resolved', 'closed_inactivity')",
}
OVERDUE_FILTER = """
    EXISTS (SELECT 1 FROM ticket_sla_cycles c JOIN ticket_sla_milestones m ON m.cycle_id = c.id
            WHERE c.ticket_id = t.id AND c.ended_at IS NULL AND m.result IS NULL
              AND (m.breached_at IS NOT NULL OR (t.status = 'open' AND m.paused_work_us IS NULL AND m.deadline_at < %s)))
"""


def ticket_json(ticket, account, sla=None):
    data = {
        "id": ticket["id"],
        "subject": ticket["subject"],
        "priority": ticket["priority"],
        "customer_blocked": bool(ticket["customer_blocked"]),
        "status": ticket["status"],
        "created_at": utc_iso(ticket["created_at"]),
    }
    if ticket["closed_at"] is not None:
        data["closed_at"] = utc_iso(ticket["closed_at"])
        data["reopen_until"] = utc_iso(reopen_until(ticket))
    if account["role"] in STAFF_ROLES:
        data.update(
            customer_name=ticket["customer_name"],
            owner_id=ticket["owner_id"],
            owner_name=ticket["owner_name"],
            ownership_version=ticket["ownership_version"],
        )
        if sla is not None:
            data["sla"] = sla
        if ticket["waiting_until"] is not None:
            data["waiting_until"] = utc_iso(ticket["waiting_until"])
    return data


def can_view(ticket, account):
    if account["role"] == "customer":
        return ticket["customer_id"] == account["id"]
    return account["role"] in MANAGEMENT_ROLES or ticket["owner_id"] in (None, account["id"])


def not_found():
    return error_response("Ticket not found.", 404)


def ownership_conflict():
    return error_response("This ticket was just reassigned. Refresh and try again.", 409, code="ownership_changed")


def lock_active_action(connection, ticket_id):
    lock_calendar(connection)
    ticket = lock_ticket(connection, ticket_id)
    if ticket is not None and expire_wait(connection, ticket, now_utc()):
        connection.commit()
    return ticket


def ticket_event(connection, action, account_id, ticket_id, details, *, occurred_at=None):
    record_event(
        connection, action, actor_id=account_id, entity_type="ticket", entity_id=ticket_id,
        details=details, occurred_at=occurred_at,
    )


def write_message(connection, ticket_id, author_id, visibility, body, posted_at):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO ticket_messages (ticket_id, author_id, visibility, body, created_at)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (ticket_id, author_id, visibility, body, posted_at),
        )
        return cursor.lastrowid


def valid_text(value, maximum):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= maximum:
        return False
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True


def valid_version(value):
    return type(value) is int and value >= 0


@tickets.get("")
@require_roles("customer", *STAFF_ROLES)
def list_tickets():
    account = current_account()
    staff = account["role"] in STAFF_ROLES
    scope = request.args.get("scope", "mine")
    selected = request.args.get("filter", "all")
    if selected == "overdue" and not staff:
        return error_response("You do not have access to SLA filters.", 403)
    if selected not in ("all", "overdue", *STATUS_FILTERS):
        return error_response("Choose a valid ticket filter.", 400)
    before = request.args.get("before", type=int)
    if "before" in request.args and (before is None or before < 1):
        return error_response("Invalid ticket page.", 400)

    conditions, values = [], []
    if scope == "mine":
        conditions.append("t.customer_id = %s" if account["role"] == "customer" else "t.owner_id = %s")
        values.append(account["id"])
    elif scope == "queue" and account["role"] in STAFF_ROLES:
        conditions.append("t.owner_id IS NULL AND t.status IN ('open', 'waiting_on_customer')")
    elif scope != "all" or account["role"] not in MANAGEMENT_ROLES:
        return error_response("You do not have access to this ticket list.", 403)
    at = now_utc()
    with get_db().cursor() as cursor:
        scope_where = " WHERE " + " AND ".join(conditions) if conditions else ""
        count_columns = ["COUNT(*) AS all_count"]
        count_columns.extend(f"SUM({condition}) AS {name}_count" for name, condition in STATUS_FILTERS.items())
        if staff:
            count_columns.append(f"SUM({OVERDUE_FILTER}) AS overdue_count")
        cursor.execute(
            f"SELECT {', '.join(count_columns)} FROM tickets t {scope_where}",
            (at, *values) if staff else values,
        )
        summary = {key.removesuffix("_count"): int(value or 0) for key, value in cursor.fetchone().items()}

        if selected == "overdue":
            conditions.append(OVERDUE_FILTER)
            values.append(at)
        elif selected in STATUS_FILTERS:
            conditions.append(STATUS_FILTERS[selected])
        if before is not None:
            conditions.append("t.id < %s")
            values.append(before)
        where = " WHERE " + " AND ".join(conditions) if conditions else ""
        cursor.execute(
            f"SELECT {TICKET_COLUMNS} {TICKET_FROM} {where} ORDER BY t.id DESC LIMIT %s",
            (*values, PAGE_SIZE + 1),
        )
        rows = cursor.fetchall()

    page = rows[:PAGE_SIZE]
    slas = ticket_slas(get_db(), page, at) if staff else {}
    return jsonify(
        tickets=[ticket_json(ticket, account, slas.get(ticket["id"])) for ticket in page],
        next_before=page[-1]["id"] if len(rows) > PAGE_SIZE else None,
        summary=summary,
    )


@tickets.post("")
@require_roles("customer")
def create_ticket():
    account = current_account()
    payload, files = message_submission()
    subject, description = payload.get("subject"), payload.get("description")
    blocked = payload.get("customer_blocked", False)
    if not valid_text(subject, 180) or not valid_text(description, MESSAGE_LENGTH):
        return error_response("Enter a subject (up to 180 characters) and a description (up to 8,000 characters).", 400)
    if type(blocked) is not bool:
        return error_response("Choose whether you can work.", 400)

    priority = "urgent" if blocked else "medium"
    connection = get_db()
    with stage_attachments(files) as attachments:
        lock_calendar(connection)
        created_at = now_utc()
        calendar = load_calendar(connection, locked=True)
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO tickets (customer_id, subject, priority, customer_blocked, created_at)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (account["id"], subject.strip(), priority, blocked, created_at),
            )
            ticket_id = cursor.lastrowid
        message_id = write_message(connection, ticket_id, account["id"], "public", description.strip(), created_at)
        attachments.link(connection, message_id)
        deadlines = start_cycle(connection, ticket_id, priority, created_at, calendar)
        ticket_event(connection, "ticket_created", account["id"], ticket_id, {
            "priority": priority, "customer_blocked": blocked, "message_id": message_id,
            "attachment_count": len(files), "deadlines": deadlines,
        }, occurred_at=created_at)
        attachments.commit(connection)
    return jsonify(id=ticket_id), 201


@tickets.get("/<int:ticket_id>")
@require_roles("customer", *STAFF_ROLES)
def ticket_detail(ticket_id):
    account = current_account()
    staff = account["role"] in STAFF_ROLES
    with get_db().cursor() as cursor:
        cursor.execute(f"SELECT {TICKET_COLUMNS} {TICKET_FROM} WHERE t.id = %s", (ticket_id,))
        ticket = cursor.fetchone()
        if ticket is None or not can_view(ticket, account):
            return not_found()

        # Filter private messages before retrieving any rows for a customer.
        public_only = "" if staff else "AND message.visibility = 'public'"
        cursor.execute(
            f"""
            SELECT message.id, message.author_id, message.visibility, message.body, message.created_at, author.name AS author_name
            FROM ticket_messages message JOIN accounts author ON author.id = message.author_id
            WHERE message.ticket_id = %s {public_only} ORDER BY message.id
            """,
            (ticket_id,),
        )
        messages = cursor.fetchall()
        cursor.execute(
            f"""
            SELECT attachment.id, attachment.message_id, attachment.filename, attachment.size_bytes
            FROM ticket_attachments attachment JOIN ticket_messages message ON message.id = attachment.message_id
            WHERE message.ticket_id = %s {public_only} ORDER BY attachment.id
            """,
            (ticket_id,),
        )
        attachments_by_message = defaultdict(list)
        for attachment in cursor.fetchall():
            attachments_by_message[attachment.pop("message_id")].append(attachment)

    at = now_utc()
    owner = ticket["owner_id"]
    staff_owner = staff and owner == account["id"]
    sla = ticket_slas(get_db(), [ticket], at, include_history=True).get(ticket_id) if staff else None
    latest_public = next((message for message in reversed(messages) if message["visibility"] == "public"), None)
    can_wait = staff_owner and ticket["status"] == "open" and sla is not None and latest_public is not None and (
        sla["first_response"]["completed_at"] is not None
        and latest_public["author_id"] != ticket["customer_id"]
        and utc_iso(latest_public["created_at"]) >= sla["started_at"]
    )
    for message in messages:
        message.pop("author_id")
        message["created_at"] = utc_iso(message["created_at"])
        message["attachments"] = attachments_by_message.get(message["id"], [])
    active = ticket["status"] in ACTIVE_STATUSES
    cutoff = reopen_until(ticket)
    return jsonify(
        ticket=ticket_json(ticket, account, sla),
        messages=messages,
        actions={
            "claim": active and staff and owner is None,
            "transfer": active and staff and (owner == account["id"] or account["role"] in MANAGEMENT_ROLES),
            "reply": active and (not staff or owner == account["id"]),
            "note": active and staff,
            "priority": active and staff,
            "wait": can_wait,
            "reply_and_wait": staff_owner and ticket["status"] == "open",
            "resolve": staff_owner and active,
            "reopen": not staff and cutoff is not None and at < cutoff,
        },
    )


@tickets.post("/<int:ticket_id>/priority")
@require_roles(*STAFF_ROLES)
def change_priority(ticket_id):
    payload = json_object()
    priority, expected = payload.get("priority"), payload.get("expected_priority")
    if not all(isinstance(value, str) and value in PRIORITY_ORDER for value in (priority, expected)):
        return error_response("Choose Low, Medium, or Urgent using the current ticket priority.", 400)

    account = current_account()
    connection = get_db()
    ticket = lock_active_action(connection, ticket_id)
    if ticket is None or not can_view(ticket, account):
        return not_found()
    if ticket["status"] not in ACTIVE_STATUSES:
        return error_response("Only active tickets can change priority.", 409)
    if ticket["priority"] != expected:
        return error_response("This ticket’s priority has changed. Refresh and try again.", 409)
    if expected == priority:
        return jsonify(id=ticket_id)

    at = now_utc()
    deadlines = apply_priority(connection, ticket_id, expected, priority, at, load_calendar(connection, locked=True))
    with connection.cursor() as cursor:
        cursor.execute("UPDATE tickets SET priority = %s WHERE id = %s", (priority, ticket_id))
    ticket_event(connection, "ticket_priority_changed", account["id"], ticket_id, {
        "old_priority": expected, "new_priority": priority, "deadlines": deadlines,
    }, occurred_at=at)
    connection.commit()
    return jsonify(id=ticket_id)


@tickets.get("/<int:ticket_id>/attachments/<int:attachment_id>")
@require_roles("customer", *STAFF_ROLES)
def download_attachment(ticket_id, attachment_id):
    account = current_account()
    allowed_messages = "AND message.visibility = 'public'" if account["role"] == "customer" else ""
    with get_db().cursor() as cursor:
        cursor.execute(
            f"""
            SELECT attachment.filename, attachment.storage_key, t.customer_id, t.owner_id
            FROM ticket_attachments attachment JOIN ticket_messages message ON message.id = attachment.message_id
            JOIN tickets t ON t.id = message.ticket_id
            WHERE attachment.id = %s AND t.id = %s {allowed_messages}
            """,
            (attachment_id, ticket_id),
        )
        attachment = cursor.fetchone()
    if attachment is None or not can_view(attachment, account):
        return error_response("Attachment not found.", 404)

    response = send_from_directory(
        current_app.config["ATTACHMENT_DIRECTORY"], attachment["storage_key"],
        as_attachment=True, download_name=attachment["filename"], mimetype="application/octet-stream",
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@tickets.get("/agents")
@require_roles(*STAFF_ROLES)
def eligible_agents():
    with get_db().cursor() as cursor:
        cursor.execute("SELECT id, name, email FROM accounts WHERE role = 'agent' AND is_active ORDER BY name, id")
        return jsonify(agents=cursor.fetchall())


def change_owner(connection, ticket_id, owner_id):
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE tickets SET owner_id = %s, ownership_version = ownership_version + 1 WHERE id = %s",
            (owner_id, ticket_id),
        )


@tickets.post("/<int:ticket_id>/claim")
@require_roles(*STAFF_ROLES)
def claim_ticket(ticket_id):
    version = json_object().get("ownership_version")
    if not valid_version(version):
        return error_response("Refresh the ticket before claiming it.", 400)
    account = current_account()
    connection = get_db()
    ticket = lock_active_action(connection, ticket_id)
    if ticket is None:
        return not_found()
    if ticket["status"] not in ACTIVE_STATUSES:
        return error_response("Only active tickets can be claimed.", 409)
    if ticket["owner_id"] is not None:
        with connection.cursor() as cursor:
            cursor.execute("SELECT name FROM accounts WHERE id = %s", (ticket["owner_id"],))
            owner = cursor.fetchone()["name"]
        return error_response(f"{owner} already owns this ticket.", 409, code="ownership_changed")
    if version != ticket["ownership_version"]:
        return ownership_conflict()

    change_owner(connection, ticket_id, account["id"])
    ticket_event(connection, "ticket_claimed", account["id"], ticket_id, {"from_owner_id": None, "to_owner_id": account["id"]})
    connection.commit()
    return jsonify(id=ticket_id)


@tickets.post("/<int:ticket_id>/transfer")
@require_roles(*STAFF_ROLES)
def transfer_ticket(ticket_id):
    payload = json_object()
    target_id, version, reason = payload.get("agent_id"), payload.get("ownership_version"), payload.get("reason", "")
    if type(target_id) is not int or target_id < 1 or not valid_version(version):
        return error_response("Choose an agent and use the current ticket version.", 400)
    if not isinstance(reason, str) or len(reason.strip()) > 500:
        return error_response("Keep the transfer reason within 500 characters.", 400)

    account = current_account()
    connection = get_db()
    ticket = lock_active_action(connection, ticket_id)
    if ticket is None:
        return not_found()
    if version != ticket["ownership_version"]:
        return ownership_conflict()
    owner = ticket["owner_id"]
    if owner != account["id"] and account["role"] not in MANAGEMENT_ROLES:
        return error_response("Only the owner or a manager can transfer this ticket.", 403)
    if ticket["status"] not in ACTIVE_STATUSES:
        return error_response("Only active tickets can be assigned or transferred.", 409)
    if target_id == owner:
        return error_response("This agent already owns the ticket.", 400)

    with connection.cursor() as cursor:
        cursor.execute("SELECT id FROM accounts WHERE id = %s AND role = 'agent' AND is_active LOCK IN SHARE MODE", (target_id,))
        if cursor.fetchone() is None:
            return error_response("Choose an active agent.", 400)

    change_owner(connection, ticket_id, target_id)
    details = {"from_owner_id": owner, "to_owner_id": target_id}
    if reason.strip():
        details["reason"] = reason.strip()
    action = "ticket_assigned" if owner is None else "ticket_transferred"
    ticket_event(connection, action, account["id"], ticket_id, details)
    connection.commit()
    return jsonify(id=ticket_id)


def lifecycle_action(ticket_id, action):
    account = current_account()
    version = json_object().get("ownership_version")
    if not valid_version(version):
        return error_response("Refresh the ticket before making this change.", 400)
    connection = get_db()
    ticket = lock_active_action(connection, ticket_id)
    if ticket is None:
        return not_found()
    if version != ticket["ownership_version"]:
        return ownership_conflict()
    if ticket["owner_id"] != account["id"]:
        return error_response("Only the assigned agent can make this change.", 403)
    if ticket["status"] not in ACTIVE_STATUSES:
        return error_response("This ticket is already closed.", 409)

    at = now_utc()
    if expire_wait(connection, ticket, at):
        connection.commit()
        return error_response("This ticket has closed for inactivity.", 409)
    if action == "wait":
        if ticket["status"] != "open":
            return error_response("This ticket is already waiting on the customer.", 409)
        message_id = qualifying_reply(connection, ticket)
        if message_id is None:
            return error_response("Send a public reply after the customer’s latest message before waiting.", 409)
        mark_waiting(connection, ticket, account["id"], message_id, at, load_calendar(connection, locked=True))
    else:
        if ticket["status"] == "waiting_on_customer":
            resume_wait(connection, ticket, account["id"], at, load_calendar(connection, locked=True), reason="resolved")
        close_cycle(connection, ticket, account["id"], "resolved", at)
    connection.commit()
    return jsonify(id=ticket_id)


@tickets.post("/<int:ticket_id>/wait")
@require_roles(*STAFF_ROLES)
def wait_for_customer(ticket_id):
    return lifecycle_action(ticket_id, "wait")


@tickets.post("/<int:ticket_id>/resolve")
@require_roles(*STAFF_ROLES)
def resolve(ticket_id):
    return lifecycle_action(ticket_id, "resolve")


@tickets.post("/<int:ticket_id>/reopen")
@require_roles("customer")
def reopen(ticket_id):
    account = current_account()
    connection = get_db()
    lock_calendar(connection)
    ticket = lock_ticket(connection, ticket_id)
    if ticket is None or not can_view(ticket, account):
        return not_found()
    at = now_utc()
    expired = expire_wait(connection, ticket, at)
    cutoff = reopen_until(ticket)
    if cutoff is None or at >= cutoff:
        if expired:
            connection.commit()
        return reopen_error(ticket)
    reopen_ticket(connection, ticket, account["id"], at, load_calendar(connection, locked=True))
    connection.commit()
    return jsonify(id=ticket_id)


def reopen_error(ticket):
    if ticket["status"] in ACTIVE_STATUSES:
        return error_response("This ticket is already active.", 409)
    return error_response("The seven-day reopening window has ended. Open a new ticket to continue.", 409, code="reopen_window_ended")


def add_message(ticket_id, visibility):
    account = current_account()
    payload, files = message_submission()
    body = payload.get("body", "")
    attachment_only = files and isinstance(body, str) and not body.strip()
    if "visibility" in payload or not (attachment_only or valid_text(body, MESSAGE_LENGTH)):
        return error_response("Enter a message of up to 8,000 characters or attach a file.", 400)
    staff_reply = visibility == "public" and account["role"] in STAFF_ROLES
    wait_requested = payload.get("wait_for_customer", False)
    if type(wait_requested) is not bool or wait_requested and not staff_reply:
        return error_response("Waiting requires a public reply from the assigned agent.", 400)

    connection = get_db()
    with stage_attachments(files) as attachments:
        lock_calendar(connection)
        ticket = lock_ticket(connection, ticket_id)
        if ticket is None:
            return not_found()
        if staff_reply:
            version = payload.get("ownership_version")
            if not valid_version(version):
                return error_response("Refresh the ticket before replying.", 400)
            if version != ticket["ownership_version"]:
                return ownership_conflict()
            if ticket["owner_id"] != account["id"]:
                return error_response("Only the assigned agent can reply to the customer.", 403)
        elif not can_view(ticket, account):
            return not_found()
        posted_at = now_utc()
        expired = expire_wait(connection, ticket, posted_at)
        customer_reply = account["role"] == "customer"
        if ticket["status"] in CLOSED_STATUSES:
            cutoff = reopen_until(ticket)
            if not customer_reply or cutoff is None or posted_at >= cutoff:
                if expired:
                    connection.commit()
                return reopen_error(ticket) if customer_reply else error_response("This ticket is closed to new staff messages.", 409)
            reopen_ticket(connection, ticket, account["id"], posted_at, load_calendar(connection, locked=True))
        if wait_requested and ticket["status"] != "open":
            return error_response("This ticket is already waiting on the customer.", 409)

        message_id = write_message(connection, ticket_id, account["id"], visibility, body.strip(), posted_at)
        attachments.link(connection, message_id)
        action = "ticket_note_added" if visibility == "private" else "ticket_reply_posted"
        ticket_event(connection, action, account["id"], ticket_id, {
            "message_id": message_id, "attachment_count": len(files),
        }, occurred_at=posted_at)
        if staff_reply:
            complete_first_response(connection, ticket_id, account["id"], posted_at)
            queue_reply(connection, ticket_id, message_id, account["id"], posted_at)
        if wait_requested:
            mark_waiting(connection, ticket, account["id"], message_id, posted_at, load_calendar(connection, locked=True))
        elif customer_reply and ticket["status"] == "waiting_on_customer":
            resume_wait(connection, ticket, account["id"], posted_at, load_calendar(connection, locked=True),
                        reason="customer_reply", message_id=message_id)
        attachments.commit(connection)
    return jsonify(id=message_id), 201


@tickets.post("/<int:ticket_id>/replies")
@require_roles("customer", *STAFF_ROLES)
def reply_to_ticket(ticket_id):
    return add_message(ticket_id, "public")


@tickets.post("/<int:ticket_id>/notes")
@require_roles(*STAFF_ROLES)
def note_on_ticket(ticket_id):
    return add_message(ticket_id, "private")
