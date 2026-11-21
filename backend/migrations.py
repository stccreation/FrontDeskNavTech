import os
from contextlib import closing

import click
import pymysql
from flask import current_app
from flask.cli import with_appcontext


def create_accounts_and_audit(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS accounts (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(120) NOT NULL,
            email VARCHAR(254) COLLATE utf8mb4_bin NOT NULL UNIQUE,
            password_hash VARCHAR(255) NOT NULL,
            role ENUM('customer', 'agent', 'manager', 'admin') NOT NULL,
            is_active BOOLEAN NOT NULL DEFAULT TRUE,
            created_at DATETIME(6) NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS audit_events (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            occurred_at DATETIME(6) NOT NULL,
            actor_account_id BIGINT UNSIGNED NULL,
            action VARCHAR(80) NOT NULL,
            entity_type VARCHAR(40) NOT NULL,
            entity_id BIGINT UNSIGNED NOT NULL,
            details JSON NOT NULL,
            INDEX audit_entity (entity_type, entity_id, id),
            FOREIGN KEY (actor_account_id) REFERENCES accounts(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )

    for operation in ("UPDATE", "DELETE"):
        name = f"audit_events_no_{operation.lower()}"
        cursor.execute(
            "SELECT 1 FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE() AND TRIGGER_NAME = %s",
            (name,),
        )
        if cursor.fetchone() is None:
            cursor.execute(
                f"""
                CREATE TRIGGER {name} BEFORE {operation} ON audit_events FOR EACH ROW
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Audit events are append-only'
                """
            )


def create_tickets_and_messages(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS tickets (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            customer_id BIGINT UNSIGNED NOT NULL,
            owner_id BIGINT UNSIGNED NULL,
            ownership_version BIGINT UNSIGNED NOT NULL DEFAULT 0,
            subject VARCHAR(180) NOT NULL,
            priority ENUM('urgent', 'medium', 'low') NOT NULL,
            customer_blocked BOOLEAN NOT NULL,
            status ENUM('open', 'waiting_on_customer', 'resolved', 'closed_inactivity') NOT NULL DEFAULT 'open',
            created_at DATETIME(6) NOT NULL,
            INDEX tickets_customer (customer_id, id),
            INDEX tickets_owner (owner_id, id),
            FOREIGN KEY (customer_id) REFERENCES accounts(id),
            FOREIGN KEY (owner_id) REFERENCES accounts(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS ticket_messages (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            ticket_id BIGINT UNSIGNED NOT NULL,
            author_id BIGINT UNSIGNED NOT NULL,
            visibility ENUM('public', 'private') NOT NULL,
            body TEXT NOT NULL,
            created_at DATETIME(6) NOT NULL,
            INDEX ticket_messages_timeline (ticket_id, id),
            INDEX ticket_messages_public (ticket_id, visibility, id),
            FOREIGN KEY (ticket_id) REFERENCES tickets(id),
            FOREIGN KEY (author_id) REFERENCES accounts(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


def add_staff_management(cursor):
    cursor.execute(
        """
        SELECT COLUMN_NAME FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'accounts'
        """
    )
    columns = {row[0] for row in cursor.fetchall()}
    if "manager_id" not in columns:
        cursor.execute(
            """
            ALTER TABLE accounts ADD COLUMN manager_id BIGINT UNSIGNED NULL,
            ADD INDEX accounts_manager (manager_id, id),
            ADD CONSTRAINT accounts_manager_fk FOREIGN KEY (manager_id) REFERENCES accounts(id)
            """
        )
    if "must_change_password" not in columns:
        cursor.execute("ALTER TABLE accounts ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE")
    if "password_version" not in columns:
        cursor.execute("ALTER TABLE accounts ADD COLUMN password_version BIGINT UNSIGNED NOT NULL DEFAULT 0")


def create_ticket_attachments(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS ticket_attachments (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            message_id BIGINT UNSIGNED NOT NULL,
            storage_key CHAR(32) CHARACTER SET ascii NOT NULL UNIQUE,
            filename VARCHAR(255) NOT NULL,
            size_bytes INT UNSIGNED NOT NULL,
            INDEX ticket_attachments_message (message_id, id),
            FOREIGN KEY (message_id) REFERENCES ticket_messages(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


def create_sla_tables(cursor):
    cursor.execute(
        """CREATE TABLE IF NOT EXISTS sla_calendar_lock (id TINYINT NOT NULL PRIMARY KEY) ENGINE=InnoDB"""
    )
    cursor.execute("INSERT IGNORE INTO sla_calendar_lock (id) VALUES (1)")
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS holiday_events (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            holiday_date DATE NOT NULL,
            name VARCHAR(120) NOT NULL,
            is_holiday BOOLEAN NOT NULL,
            effective_at DATETIME(6) NOT NULL,
            INDEX holiday_event_date (holiday_date, effective_at, id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS ticket_sla_cycles (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            ticket_id BIGINT UNSIGNED NOT NULL,
            cycle_number INT UNSIGNED NOT NULL,
            started_at DATETIME(6) NOT NULL,
            ended_at DATETIME(6) NULL,
            UNIQUE KEY ticket_cycle (ticket_id, cycle_number),
            FOREIGN KEY (ticket_id) REFERENCES tickets(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS ticket_sla_milestones (
            cycle_id BIGINT UNSIGNED NOT NULL,
            milestone ENUM('first_response', 'resolution') NOT NULL,
            deadline_at DATETIME(6) NOT NULL,
            deadline_kind ENUM('working_time', 'day_end') NOT NULL,
            completed_at DATETIME(6) NULL,
            breached_at DATETIME(6) NULL,
            result ENUM('met', 'late', 'not_applicable') NULL,
            PRIMARY KEY (cycle_id, milestone),
            INDEX pending_sla (result, breached_at, deadline_at),
            FOREIGN KEY (cycle_id) REFERENCES ticket_sla_cycles(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


def add_ticket_lifecycle(cursor):
    for table, definitions in (
        ("tickets", {
            "waiting_since": "DATETIME(6) NULL",
            "waiting_until": "DATETIME(6) NULL",
            "waiting_message_id": "BIGINT UNSIGNED NULL",
            "closed_at": "DATETIME(6) NULL",
        }),
        ("ticket_sla_cycles", {"closure_status": "ENUM('resolved', 'closed_inactivity') NULL"}),
        ("ticket_sla_milestones", {"paused_work_us": "BIGINT UNSIGNED NULL"}),
    ):
        cursor.execute(
            "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s",
            (table,),
        )
        columns = {row[0] for row in cursor.fetchall()}
        for name, definition in definitions.items():
            if name not in columns:
                cursor.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")
    cursor.execute(
        "SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tickets' AND INDEX_NAME = 'ticket_inactivity'"
    )
    if cursor.fetchone() is None:
        cursor.execute("CREATE INDEX ticket_inactivity ON tickets (status, waiting_until, id)")


def create_reply_notifications(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS reply_notifications (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            ticket_id BIGINT UNSIGNED NOT NULL,
            message_id BIGINT UNSIGNED NOT NULL UNIQUE,
            status ENUM('queued', 'sent', 'failed') NOT NULL DEFAULT 'queued',
            queued_at DATETIME(6) NOT NULL,
            claimed_at DATETIME(6) NULL,
            sent_at DATETIME(6) NULL,
            failed_at DATETIME(6) NULL,
            failure_reason VARCHAR(64) NULL,
            delivery_confirmed_at DATETIME(6) NULL,
            INDEX notification_work (status, claimed_at, id),
            INDEX notification_period (queued_at, status),
            FOREIGN KEY (ticket_id) REFERENCES tickets(id),
            FOREIGN KEY (message_id) REFERENCES ticket_messages(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


MIGRATIONS = (
    ("001_accounts_and_audit", create_accounts_and_audit),
    ("002_tickets_and_messages", create_tickets_and_messages),
    ("003_staff_management", add_staff_management),
    ("004_ticket_attachments", create_ticket_attachments),
    ("005_sla_calendar", create_sla_tables),
    ("006_ticket_lifecycle", add_ticket_lifecycle),
    ("007_reply_notifications", create_reply_notifications),
)


@click.command("db-upgrade")
@click.option("--user", default="root", show_default=True, help="Database migration account.")
@click.option("--ask-password", is_flag=True, help="Prompt for the migration account password.")
@with_appcontext
def db_upgrade(user, ask_password):
    password = click.prompt("Database password", hide_input=True) if ask_password else os.getenv("DB_MIGRATION_PASSWORD", "")
    settings = current_app.config["DATABASE_SETTINGS"] | {"user": user, "password": password}

    with closing(pymysql.connect(**settings, autocommit=True)) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT GET_LOCK(SHA2(CONCAT('frontdesk-migrations:', DATABASE()), 256), 10)")
            if cursor.fetchone() != (1,):
                raise click.ClickException("Another migration holds the database lock.")
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version VARCHAR(80) NOT NULL PRIMARY KEY,
                    applied_at DATETIME(6) NOT NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )
            cursor.execute("SELECT version FROM schema_migrations")
            applied = {row[0] for row in cursor.fetchall()}
            for version, migrate in MIGRATIONS:
                if version in applied:
                    continue
                migrate(cursor)
                cursor.execute("INSERT INTO schema_migrations VALUES (%s, UTC_TIMESTAMP(6))", (version,))
                click.echo(f"Applied {version}")

    click.echo("Database is up to date.")
