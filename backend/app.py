import os
from contextlib import closing
from datetime import timedelta
from pathlib import Path

import pymysql
from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_from_directory

from attachments import AttachmentError
from audit import recent_events
from auth import MANAGEMENT_ROLES, auth, check_api_csrf, error_response, require_roles, staff_create
from database import close_db, get_db
from holidays import holidays
from lifecycle import ticket_lifecycle
from migrations import db_upgrade
from notifications import environment_mail, notification_worker
from reports import reports
from sla import sla_backfill, sla_check
from staff import staff
from tickets import tickets


BACKEND_DIR = Path(__file__).resolve().parent
WEB_BUILD_DIR = BACKEND_DIR / "web"


def create_app():
    load_dotenv(BACKEND_DIR / ".env")
    app = Flask(__name__, static_folder=None)
    secret_key = os.getenv("SECRET_KEY", "")
    if len(secret_key) < 32 or secret_key.startswith("replace-with-"):
        raise RuntimeError("Set a random SECRET_KEY of at least 32 characters in backend/.env.")
    app.config.from_mapping(
        FRONTDESK_MAIL=environment_mail(),
        ATTACHMENT_DIRECTORY=BACKEND_DIR / ".local" / "attachments",
        SECRET_KEY=secret_key,
        SESSION_COOKIE_NAME="frontdesk_session",
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=os.getenv("SESSION_COOKIE_SECURE", "true").lower() != "false",
        PERMANENT_SESSION_LIFETIME=timedelta(hours=12),
        SESSION_REFRESH_EACH_REQUEST=False,
    )
    app.config["DATABASE_SETTINGS"] = database_settings = {
        "host": os.getenv("DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("DB_PORT", "3306")),
        "database": os.getenv("DB_NAME", "frontdesk"),
        "user": os.getenv("DB_USER", "frontdesk"),
        "password": os.getenv("DB_PASSWORD", ""),
        "charset": "utf8mb4",
        "connect_timeout": 2,
        "read_timeout": 2,
        "write_timeout": 2,
    }
    app.register_blueprint(auth)
    app.register_blueprint(holidays)
    app.register_blueprint(reports)
    app.register_blueprint(staff)
    app.register_blueprint(tickets)
    app.before_request(check_api_csrf)
    app.teardown_appcontext(close_db)
    app.cli.add_command(db_upgrade)
    app.cli.add_command(sla_backfill)
    app.cli.add_command(sla_check)
    app.cli.add_command(ticket_lifecycle)
    app.cli.add_command(notification_worker)
    app.cli.add_command(staff_create)

    @app.after_request
    def disable_api_caching(response):
        if request.path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    @app.errorhandler(413)
    def request_too_large(_error):
        return error_response("The request is too large.", 413)

    @app.errorhandler(AttachmentError)
    def attachment_error(error):
        return error_response(str(error), error.status)

    @app.errorhandler(pymysql.OperationalError)
    @app.errorhandler(pymysql.InterfaceError)
    def database_error(error):
        app.logger.error("Database request failed", exc_info=error)
        return error_response("The database is temporarily unavailable.", 503)

    @app.get("/api/health")
    def health():
        try:
            with closing(pymysql.connect(**database_settings)) as connection:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT 1")
                    cursor.fetchone()
        except (OSError, pymysql.MySQLError):
            return jsonify(status="degraded", database="unavailable"), 503

        return jsonify(status="ok", database="connected")

    @app.get("/api/audit")
    @require_roles(*MANAGEMENT_ROLES)
    def audit_history():
        return jsonify(events=recent_events(get_db()))

    @app.get("/")
    def index():
        return send_from_directory(WEB_BUILD_DIR, "index.html")

    @app.get("/<path:asset>")
    def web_asset(asset):
        return send_from_directory(WEB_BUILD_DIR, asset)

    return app
