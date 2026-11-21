from flask import Blueprint, jsonify

from audit import record_event
from auth import (
    MANAGEMENT_ROLES, EmailAlreadyRegistered, create_account, current_account,
    error_response, json_object, lock_active_manager, require_roles,
)
from database import get_db


staff = Blueprint("staff", __name__, url_prefix="/api/staff")


def valid_account_id(value):
    return type(value) is int and 0 < value < 2**64


@staff.get("")
@require_roles(*MANAGEMENT_ROLES)
def list_staff():
    actor = current_account()
    is_admin = actor["role"] == "admin"
    managers = []
    with get_db().cursor() as cursor:
        if is_admin:
            cursor.execute("SELECT id, name, email, is_active FROM accounts WHERE role = 'manager' ORDER BY name, id")
            managers = list(cursor.fetchall())
        team_filter = "" if is_admin else "AND agent.manager_id = %s"
        cursor.execute(
            f"""
            SELECT agent.id, agent.name, agent.email, agent.is_active, agent.manager_id,
                   manager.name AS manager_name, manager.is_active AS manager_active
            FROM accounts agent LEFT JOIN accounts manager ON manager.id = agent.manager_id
            WHERE agent.role = 'agent' {team_filter} ORDER BY agent.name, agent.id
            """,
            () if is_admin else (actor["id"],),
        )
        agents = list(cursor.fetchall())

    for account in managers + agents:
        account["is_active"] = bool(account["is_active"])
        if account.get("manager_active") is not None:
            account["manager_active"] = bool(account["manager_active"])
    return jsonify(managers=managers, agents=agents)


@staff.post("")
@require_roles(*MANAGEMENT_ROLES)
def add_staff():
    actor = current_account()
    payload = json_object()
    role = payload.get("role", "agent")
    manager_id = payload.get("manager_id")
    if actor["role"] == "manager":
        if role != "agent" or "manager_id" in payload:
            return error_response("Managers create agents for their own team.", 403)
        manager_id = actor["id"]
    elif role == "agent":
        if not valid_account_id(manager_id):
            return error_response("Choose an active manager for the agent.", 400)
    elif role != "manager" or manager_id is not None:
        return error_response("Choose a manager or support agent account.", 400)

    try:
        account = create_account(
            payload.get("name"), payload.get("email"), payload.get("temporary_password"), role,
            actor_id=actor["id"], manager_id=manager_id, must_change_password=True,
        )
    except ValueError as error:
        return error_response(str(error), 400)
    except EmailAlreadyRegistered:
        return error_response("An account already uses that email address.", 409)
    return jsonify(id=account["id"]), 201


@staff.post("/<int:agent_id>/manager")
@require_roles("admin")
def move_agent(agent_id):
    payload = json_object()
    manager_id = payload.get("manager_id")
    expected = payload.get("expected_manager_id")
    if not valid_account_id(manager_id) or "expected_manager_id" not in payload:
        return error_response("Choose an active manager and use the current team assignment.", 400)
    if expected is not None and not valid_account_id(expected):
        return error_response("Use the current team assignment.", 400)

    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute("SELECT manager_id FROM accounts WHERE id = %s AND role = 'agent' FOR UPDATE", (agent_id,))
        agent = cursor.fetchone()
        if agent is None:
            return error_response("Support agent not found.", 404)
        old_manager = agent["manager_id"]
        if old_manager != expected:
            return error_response("This agent’s team has just changed. Refresh and try again.", 409, code="team_changed")
        if old_manager == manager_id:
            return error_response("This agent already belongs to that manager.", 400)
        if not lock_active_manager(cursor, manager_id):
            return error_response("Choose an active manager.", 400)
        cursor.execute("UPDATE accounts SET manager_id = %s WHERE id = %s", (manager_id, agent_id))

    record_event(
        connection, "staff_manager_changed", actor_id=current_account()["id"],
        entity_type="account", entity_id=agent_id,
        details={"from_manager_id": old_manager, "to_manager_id": manager_id},
    )
    connection.commit()
    return jsonify(id=agent_id)
