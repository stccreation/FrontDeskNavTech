import re
from email.message import EmailMessage
from functools import wraps
from getpass import getuser
from hashlib import sha256
from secrets import compare_digest, token_hex, token_urlsafe

import click
import pymysql
from email_validator import EmailNotValidError, validate_email
from flask import Blueprint, g, jsonify, request, session
from flask.cli import with_appcontext
from werkzeug.security import check_password_hash, generate_password_hash

from audit import record_event
from database import get_db
from notifications import delivery_settings, send_mail


auth = Blueprint("auth", __name__, url_prefix="/api/auth")
STAFF_ROLES = ("agent", "manager", "admin")
MANAGEMENT_ROLES = ("manager", "admin")
ACCOUNT_FIELDS = "id, name, email, role, must_change_password, password_version"
PASSWORD_LENGTH_ERROR = "Use a password between 15 and 128 characters."
DUMMY_PASSWORD_HASH = generate_password_hash(token_hex(32))
VERIFICATION_TOKEN = re.compile(r"[A-Za-z0-9_-]{43}")


class EmailAlreadyRegistered(Exception):
    pass


def normalize_email(value):
    if not isinstance(value, str) or len(value) > 254:
        raise ValueError("Enter a valid email address.")
    try:
        return validate_email(value.strip(), check_deliverability=False).normalized.lower()
    except EmailNotValidError:
        raise ValueError("Enter a valid email address.") from None


def error_response(message, status, *, code=None):
    return jsonify(error=message, code=code), status


def csrf_token():
    if "csrf_token" not in session:
        session["csrf_token"] = token_urlsafe(32)
    return session["csrf_token"]


def check_api_csrf():
    if not request.path.startswith("/api/") or request.method in ("GET", "HEAD", "OPTIONS"):
        return None
    expected = session.get("csrf_token")
    provided = request.headers.get("X-CSRF-Token", "")
    if not expected or not compare_digest(expected.encode(), provided.encode()):
        return error_response("Your session has changed. Refresh and try again.", 403, code="invalid_csrf")
    return None


def current_account():
    if "account" not in g:
        g.account = None
        account_id = session.get("account_id")
        if account_id is not None:
            with get_db().cursor() as cursor:
                cursor.execute(f"SELECT {ACCOUNT_FIELDS} FROM accounts WHERE id = %s AND is_active", (account_id,))
                g.account = cursor.fetchone()
            if g.account is None or g.account["password_version"] != session.get("password_version", 0):
                g.account = None
                session.clear()
    return g.account


def require_roles(*roles):
    def decorate(view):
        @wraps(view)
        def protected(*args, **kwargs):
            account = current_account()
            if account is None:
                return error_response("Sign in to continue.", 401)
            if account["role"] not in roles:
                return error_response("You do not have access to this resource.", 403)
            if account["must_change_password"]:
                return error_response("Choose a permanent password to continue.", 403, code="password_change_required")
            return view(*args, **kwargs)

        return protected

    return decorate


def valid_password(password):
    if not isinstance(password, str) or not 15 <= len(password) <= 128:
        return False
    try:
        password.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True


def normalize_name(name):
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 120:
        raise ValueError("Enter a name between 1 and 120 characters.")
    return name.strip()


def lock_active_manager(cursor, manager_id):
    cursor.execute(
        "SELECT id FROM accounts WHERE id = %s AND role = 'manager' AND is_active LOCK IN SHARE MODE",
        (manager_id,),
    )
    return cursor.fetchone() is not None


def create_account(
    name, email, password, role, *, operator=None, actor_id=None,
    manager_id=None, must_change_password=False,
):
    name = normalize_name(name)
    email = normalize_email(email)
    if not valid_password(password):
        raise ValueError(PASSWORD_LENGTH_ERROR)
    password_hash = generate_password_hash(password)

    connection = get_db()
    try:
        with connection.cursor() as cursor:
            if manager_id is not None and not lock_active_manager(cursor, manager_id):
                raise ValueError("Choose an active manager.")
            cursor.execute(
                """
                INSERT INTO accounts (name, email, password_hash, role, manager_id, must_change_password, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, UTC_TIMESTAMP(6))
                """,
                (name, email, password_hash, role, manager_id, must_change_password),
            )
            account_id = cursor.lastrowid
        details = {"role": role}
        if role == "customer":
            details["email_verified"] = True
        if operator is not None:
            details["operator"] = operator
        if manager_id is not None:
            details["manager_id"] = manager_id
        record_event(
            connection,
            "account_registered" if role == "customer" else "staff_account_created",
            actor_id=account_id if role == "customer" else actor_id,
            entity_type="account",
            entity_id=account_id,
            details=details,
        )
        connection.commit()
    except pymysql.IntegrityError as error:
        connection.rollback()
        if error.args[0] == 1062:
            raise EmailAlreadyRegistered from None
        raise

    return {
        "id": account_id, "name": name, "email": email, "role": role,
        "must_change_password": must_change_password, "password_version": 0,
    }


def session_response(account):
    user = None
    if account is not None:
        user = {key: account[key] for key in ("id", "name", "email", "role")}
        if account["must_change_password"]:
            user["must_change_password"] = True
    return jsonify(user=user, csrf_token=csrf_token())


def sign_in(account):
    session.clear()
    session.permanent = True
    session["account_id"] = account["id"]
    session["password_version"] = account["password_version"]
    return session_response(account)


def json_object(max_bytes=8192):
    request.max_content_length = max_bytes
    payload = request.get_json(silent=True)
    return payload if isinstance(payload, dict) else {}


@auth.get("/session")
def get_session():
    return session_response(current_account())


@auth.post("/register")
def register():
    payload = json_object()
    try:
        name = normalize_name(payload.get("name"))
        email = normalize_email(payload.get("email"))
    except ValueError as error:
        return error_response(str(error), 400)
    settings = delivery_settings()
    if settings is None:
        return error_response("Customer signup is temporarily unavailable. Try again later.", 503)

    token = token_urlsafe(32)
    digest = sha256(token.encode("ascii")).digest()
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute("SELECT id FROM accounts WHERE email = %s", (email,))
        if cursor.fetchone() is not None:
            return jsonify(verification_requested=True), 202
        # Avoid repeated sends and keep the most recent issued link usable during the cooldown.
        cursor.execute(
            """
            INSERT INTO customer_verifications (email, name, token_hash, created_at)
            VALUES (%s, %s, %s, UTC_TIMESTAMP(6))
            ON DUPLICATE KEY UPDATE
                name = IF(created_at <= UTC_TIMESTAMP(6) - INTERVAL 1 MINUTE, %s, name),
                token_hash = IF(created_at <= UTC_TIMESTAMP(6) - INTERVAL 1 MINUTE, %s, token_hash),
                created_at = IF(created_at <= UTC_TIMESTAMP(6) - INTERVAL 1 MINUTE, UTC_TIMESTAMP(6), created_at)
            """,
            (email, name, digest, name, digest),
        )
        issue_link = cursor.rowcount > 0
    connection.commit()

    if issue_link:
        link = f"{settings['public_url']}/#verify={token}"
        message = EmailMessage()
        message["Subject"] = "Verify your Frontdesk email"
        message["From"] = settings["from"]
        message["To"] = email
        message.set_content(
            f"Verify your email and choose your password:\n\n{link}\n\n"
            "This link expires in one hour. If you did not request a Frontdesk account, you can ignore this email.\n"
        )
        if send_mail(settings, message, timeout=5):
            return error_response("Could not send the verification email. Try again in a minute.", 503)
    return jsonify(verification_requested=True), 202


@auth.post("/verify-email")
def verify_email():
    payload = json_object()
    token = payload.get("token")
    password = payload.get("password")
    if not valid_password(password):
        return error_response(PASSWORD_LENGTH_ERROR, 400)
    invalid_link = "This verification link is invalid, expired, or already used. Request a new link."
    if not isinstance(token, str) or not VERIFICATION_TOKEN.fullmatch(token):
        return error_response(invalid_link, 400)
    digest = sha256(token.encode("ascii")).digest()
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT email, name FROM customer_verifications
            WHERE token_hash = %s AND created_at > UTC_TIMESTAMP(6) - INTERVAL 1 HOUR
            FOR UPDATE
            """,
            (digest,),
        )
        verification = cursor.fetchone()
        if verification is None:
            return error_response(invalid_link, 400)
        cursor.execute("DELETE FROM customer_verifications WHERE token_hash = %s", (digest,))
    try:
        account = create_account(verification["name"], verification["email"], password, "customer")
    except EmailAlreadyRegistered:
        return error_response("An account already uses that email address. Sign in to continue.", 409)
    return sign_in(account), 201


@auth.post("/login")
def login():
    payload = json_object()
    password = payload.get("password")
    invalid_credentials = "Email or password is incorrect."
    try:
        email = normalize_email(payload.get("email"))
    except ValueError:
        return error_response(invalid_credentials, 401)
    if not valid_password(password):
        return error_response(invalid_credentials, 401)

    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            f"SELECT {ACCOUNT_FIELDS}, password_hash FROM accounts WHERE email = %s AND is_active",
            (email,),
        )
        account = cursor.fetchone()
    password_hash = DUMMY_PASSWORD_HASH if account is None else account.pop("password_hash")
    if not check_password_hash(password_hash, password) or account is None:
        return error_response(invalid_credentials, 401)

    record_event(connection, "account_signed_in", actor_id=account["id"], entity_type="account", entity_id=account["id"])
    connection.commit()
    return sign_in(account)


@auth.post("/password")
def choose_permanent_password():
    account = current_account()
    if account is None:
        return error_response("Sign in to continue.", 401)
    if not account["must_change_password"]:
        return error_response("This account has already chosen a permanent password.", 409)

    password = json_object().get("password")
    if not valid_password(password):
        return error_response(PASSWORD_LENGTH_ERROR, 400)
    password_hash = generate_password_hash(password)
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT password_hash, password_version FROM accounts
            WHERE id = %s AND is_active AND must_change_password FOR UPDATE
            """,
            (account["id"],),
        )
        pending = cursor.fetchone()
        if pending is None or pending["password_version"] != account["password_version"]:
            return error_response("Your password has changed. Sign in again.", 409)
        if check_password_hash(pending["password_hash"], password):
            return error_response("Choose a password that differs from your temporary password.", 400)

        cursor.execute(
            """
            UPDATE accounts SET password_hash = %s, must_change_password = FALSE,
                password_version = password_version + 1
            WHERE id = %s
            """,
            (password_hash, account["id"]),
        )
    record_event(
        connection, "staff_password_initialized", actor_id=account["id"],
        entity_type="account", entity_id=account["id"],
    )
    connection.commit()
    return sign_in(account | {"must_change_password": False, "password_version": account["password_version"] + 1})


@auth.post("/logout")
def logout():
    account = current_account()
    if account is not None:
        connection = get_db()
        record_event(connection, "account_signed_out", actor_id=account["id"], entity_type="account", entity_id=account["id"])
        connection.commit()
    session.clear()
    return session_response(None)


@click.command("staff-create")
@click.option("--name", required=True)
@click.option("--email", required=True)
@click.option("--role", type=click.Choice(STAFF_ROLES), required=True)
@click.password_option()
@with_appcontext
def staff_create(name, email, role, password):
    try:
        account = create_account(name, email, password, role, operator=getuser())
    except ValueError as error:
        raise click.ClickException(str(error)) from None
    except EmailAlreadyRegistered:
        raise click.ClickException("An account already uses that email address.") from None
    click.echo(f"Created {role} account {account['email']}.")
