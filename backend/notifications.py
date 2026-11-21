import os
import smtplib
import ssl
from datetime import timedelta
from email.message import EmailMessage
from time import sleep
from urllib.parse import urlencode, urlsplit

import click
import pymysql
from email_validator import EmailNotValidError, validate_email
from flask import current_app
from flask.cli import with_appcontext

from audit import record_event
from database import get_db
from sla import now_utc


DISPATCH_TIMEOUT = timedelta(minutes=5)
LOOPBACK = {"localhost", "127.0.0.1", "::1"}
STATUSES = ("queued", "sent", "failed")


def environment_mail():
    values = {key: os.getenv(f"FRONTDESK_SMTP_{key.upper()}", "") for key in ("host", "port", "security", "from", "user", "password")}
    return values | {"public_url": os.getenv("FRONTDESK_PUBLIC_URL", "")}


def delivery_settings():
    settings = current_app.config["FRONTDESK_MAIL"]
    host = settings["host"].strip()
    if not host or any(char.isspace() for char in host):
        return None
    security = settings["security"].strip().lower() or "starttls"
    if security not in ("starttls", "ssl") and not (security == "plain" and host in LOOPBACK):
        return None
    if bool(settings["user"]) != bool(settings["password"]):
        return None
    try:
        origin = settings["public_url"].strip()
        url = urlsplit(origin)
        port = int(settings["port"] or (465 if security == "ssl" else 587))
        sender = validate_email(settings["from"], check_deliverability=False).normalized
        if not url.hostname or url.username or url.password or url.query or url.fragment or not 1 <= port <= 65535:
            return None
        if url.scheme != "https" and not (url.scheme == "http" and url.hostname in LOOPBACK and host in LOOPBACK):
            return None
    except (ValueError, EmailNotValidError):
        return None
    return settings | {"host": host, "security": security, "port": port, "from": sender, "public_url": origin.rstrip("/")}


def queue_reply(connection, ticket_id, message_id, actor_id, at):
    with connection.cursor() as cursor:
        cursor.execute(
            "INSERT INTO reply_notifications (ticket_id, message_id, queued_at) VALUES (%s, %s, %s)",
            (ticket_id, message_id, at),
        )
        notification_id = cursor.lastrowid
    record_event(connection, "notification_queued", actor_id=actor_id, entity_type="ticket", entity_id=ticket_id,
                 occurred_at=at, details={"notification_id": notification_id, "message_id": message_id})


def claim_notification(connection, at):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT id, ticket_id, message_id FROM reply_notifications
            WHERE status = 'queued' AND claimed_at IS NULL ORDER BY id LIMIT 1 FOR UPDATE
            """
        )
        notification = cursor.fetchone()
        if notification:
            cursor.execute("UPDATE reply_notifications SET claimed_at = %s WHERE id = %s", (at, notification["id"]))
            notification["claimed_at"] = at
    connection.commit()
    if notification:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT a.email AS recipient, a.is_active FROM tickets t JOIN accounts a ON a.id = t.customer_id WHERE t.id = %s",
                (notification["ticket_id"],),
            )
            notification.update(cursor.fetchone())
    return notification


def finish_notification(connection, notification, at, failure=None):
    status = "failed" if failure else "sent"
    with connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE reply_notifications SET status = %s, sent_at = %s, failed_at = %s, failure_reason = %s
            WHERE id = %s AND status = 'queued' AND claimed_at = %s
            """,
            (status, None if failure else at, at if failure else None, failure, notification["id"], notification["claimed_at"]),
        )
        changed = cursor.rowcount == 1
    if changed:
        details = {"notification_id": notification["id"], "message_id": notification["message_id"]}
        if failure:
            details["reason"] = failure
        record_event(connection, f"notification_{status}", actor_id=None, entity_type="ticket", entity_id=notification["ticket_id"],
                     occurred_at=at, details=details)
    return changed


def expire_claims(connection, at):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT id, ticket_id, message_id, claimed_at FROM reply_notifications WHERE status = 'queued' AND claimed_at < %s LIMIT 100 FOR UPDATE",
            (at - DISPATCH_TIMEOUT,),
        )
        abandoned = cursor.fetchall()
    count = sum(finish_notification(connection, notification, at, "delivery_outcome_unknown") for notification in abandoned)
    connection.commit()
    return count


def send_link(settings, notification):
    if not notification["is_active"]:
        return "customer_inactive"
    ticket_id = notification["ticket_id"]
    link = f"{settings['public_url']}/?{urlencode({'ticket': ticket_id})}"
    message = EmailMessage()
    message["Subject"] = f"Frontdesk ticket #{ticket_id}"
    message["From"] = settings["from"]
    message["To"] = notification["recipient"]
    message.set_content(f"Ticket #{ticket_id}\n\n{link}\n")
    return send_mail(settings, message)


def send_mail(settings, message, *, timeout=10):
    server = None
    try:
        tls = ssl.create_default_context()
        args = (settings["host"], settings["port"])
        if settings["security"] == "ssl":
            server = smtplib.SMTP_SSL(*args, context=tls, timeout=timeout)
        else:
            server = smtplib.SMTP(*args, timeout=timeout)
            if settings["security"] == "starttls":
                server.starttls(context=tls)
        if settings["user"]:
            server.login(settings["user"], settings["password"])
        server.send_message(message)
    except (smtplib.SMTPResponseException, smtplib.SMTPRecipientsRefused, smtplib.SMTPNotSupportedError):
        return "smtp_rejected"
    except OSError:
        return "smtp_connection_error"
    finally:
        if server is not None:
            server.close()
    return None


def process_notifications(app, settings, batch_size):
    with app.app_context():
        failed = expire_claims(get_db(), now_utc())
    sent = 0
    for _ in range(batch_size):
        with app.app_context():
            notification = claim_notification(get_db(), now_utc())
        if notification is None:
            break
        failure = send_link(settings, notification)
        with app.app_context():
            connection = get_db()
            updated = finish_notification(connection, notification, now_utc(), failure)
            connection.commit()
        if updated:
            failed += bool(failure)
            sent += not failure
    return sent, failed


@click.command("notification-worker")
@click.option("--watch", is_flag=True, help="Keep processing queued reply notifications.")
@click.option("--interval", default=30, type=click.IntRange(min=1), show_default=True)
@with_appcontext
def notification_worker(watch, interval):
    app = current_app._get_current_object()
    settings = delivery_settings()
    if settings is None:
        if watch:
            raise click.ClickException("Configure SMTP and the Frontdesk portal URL to enable delivery.")
        click.echo("Email delivery is unconfigured. Notifications remain queued.")
        return
    while True:
        try:
            sent, failed = process_notifications(app, settings, 20)
            if sent or failed or not watch:
                click.echo(f"SMTP accepted {sent} notification(s). {failed} failed.")
        except pymysql.MySQLError as error:
            if not watch:
                raise
            click.echo(f"Notification check failed and will retry: {error.args[0]}", err=True)
        if not watch:
            return
        sleep(interval)
