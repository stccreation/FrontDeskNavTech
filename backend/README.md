# Frontdesk API

The Flask development server serves the API and the built Flutter site at `http://127.0.0.1:5000/`.

## Start the local stack

1. In the XAMPP Control Panel, start **MySQL** if it is stopped. The database listens on `127.0.0.1:3306`. To browse the `frontdesk` database in phpMyAdmin, start **Apache** and click **Admin** next to **MySQL**.

   On a fresh machine, create a `frontdesk` database and a dedicated database user. Copy `.env.example` to `.env`, set the connection details, and set `SECRET_KEY` to a random value such as the output of `python -c "import secrets; print(secrets.token_hex(32))"`. Set `SESSION_COOKIE_SECURE=true` when serving the app over HTTPS.

2. [Build the Flutter site](../frontend/README.md).
3. From `backend`, install the dependencies and apply database migrations.

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   .\.venv\Scripts\python.exe -m flask --app app db-upgrade
   ```

   By default, migrations use the local XAMPP `root` account. Use `--user` and `--ask-password` for a separate migration account. For a fresh database, grant the application account access to the new tables after the migration. Use the actual application account if it differs from the local example.

   ```sql
   GRANT SELECT, INSERT ON frontdesk.accounts TO 'frontdesk'@'127.0.0.1';
   GRANT UPDATE (manager_id, password_hash, must_change_password, password_version) ON frontdesk.accounts TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT ON frontdesk.audit_events TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT, UPDATE (owner_id, ownership_version) ON frontdesk.tickets TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT ON frontdesk.ticket_messages TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT ON frontdesk.ticket_attachments TO 'frontdesk'@'127.0.0.1';
   GRANT UPDATE (priority) ON frontdesk.tickets TO 'frontdesk'@'127.0.0.1';
   GRANT UPDATE (status, waiting_since, waiting_until, waiting_message_id, closed_at) ON frontdesk.tickets TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT ON frontdesk.sla_calendar_lock TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT ON frontdesk.holiday_events TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT ON frontdesk.ticket_sla_cycles TO 'frontdesk'@'127.0.0.1';
   GRANT UPDATE (ended_at, closure_status) ON frontdesk.ticket_sla_cycles TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT, UPDATE (deadline_at, deadline_kind, completed_at, breached_at, result) ON frontdesk.ticket_sla_milestones TO 'frontdesk'@'127.0.0.1';
   GRANT UPDATE (paused_work_us) ON frontdesk.ticket_sla_milestones TO 'frontdesk'@'127.0.0.1';
   GRANT SELECT, INSERT, UPDATE (status, claimed_at, sent_at, failed_at, failure_reason) ON frontdesk.reply_notifications TO 'frontdesk'@'127.0.0.1';
   ```

   After upgrading an existing database, initialize timing for its existing tickets before starting the new server.

   ```powershell
   .\.venv\Scripts\python.exe -m flask --app app sla-backfill
   ```

4. Start Flask from `backend`.

   ```powershell
   .\.venv\Scripts\python.exe -m flask --app app run --host 127.0.0.1 --port 5000
   ```

Open `http://127.0.0.1:5000/` to sign in or create a customer account. `GET /api/health` checks the database with `SELECT 1` and returns HTTP 503 if it is unreachable.

## Staff accounts and audit history

Public registration creates customer accounts. Admins use **Staff Management** to create managers, create agents under an active manager, and move agents between teams. Managers use the same screen to create agents for their own team. Existing agents with no manager appear as **Unassigned** for admins.

Staff created in the portal sign in with their temporary password and choose a permanent password before accessing their workspace. Creating accounts, moving agents, and setting the first permanent password are recorded in the audit history.

The `staff-create` command is available for local setup and administrative bootstrap. It prompts for the account password and supports `agent`, `manager`, and `admin` roles.

```powershell
.\.venv\Scripts\python.exe -m flask --app app staff-create --role admin --name 'Frontdesk Admin' --email 'admin@example.com'
```

Passwords must have 15 to 128 characters. `GET /api/audit` returns the latest 100 audit entries to signed-in managers and administrators. Entries record the actor, action, account affected, and UTC timestamp. Database triggers reject updates and deletes, and the application database account has read and append privileges on the history.

## Tickets

Customers use **My tickets** to open and follow their own tickets. New tickets start at Medium. The answer **No, I’m blocked** creates an Urgent ticket and flags the reported block for staff.

Staff can open the **Unassigned** queue and **Assigned to me**. Managers and administrators also have **All tickets** and can assign or transfer any active ticket. The current owner can hand over their own ticket to an active agent. Create accounts with the `agent` role to make those agents available as transfer recipients.

Only the current owner can send a public staff reply. **Private note** is a separate action and appears only in the staff conversation. Claiming, transferring, replying, and adding notes record the actor and time in the audit history.

## Attachments

Use **Attach files** when opening a ticket, sending a public reply, or adding a private note. Each submission accepts up to five files of 15 MB each. Replies and notes can contain attachments alone. A private note’s files are available only to staff who can access the ticket.

Frontdesk saves the file bytes under `backend/.local/attachments` and the attachment metadata in MariaDB. Downloads use the same ticket access rules as the conversation. Keep the attachment folder with database backups.

## Working hours and SLA deadlines

The ticket queue shows separate response and resolution overdue indicators. Ticket details show each promised deadline in IST and the first public staff response time when available. Staff can use **Change priority** on active tickets they can access. An upgrade compares each pending deadline with the new priority's promise. A downgrade keeps the existing promise.

Managers and admins use **Holidays** to add and remove dates. Edits affect future working time and write an audit entry for every deadline that moves. Completed milestones and recorded breaches retain their historical deadlines.

The provisional urgent resolution rule uses same-day close for arrivals and escalations within working hours. Outside working hours it uses the next working day's close. Review the 6:00 p.m. exception before launch.

Ticket views calculate current overdue indicators when loaded. The idempotent `sla-check` command records outstanding breaches in the audit history. Responses and timing edits also record applicable breaches as they happen.

```powershell
.\.venv\Scripts\python.exe -m unittest -v test_business_hours
.\.venv\Scripts\python.exe -m flask --app app sla-check
```

## Waiting, closure, and reopening

The assigned agent can use **Send reply and wait** or select **Waiting on customer** after the latest public reply to the customer. The status pauses the applicable SLA deadlines and starts a separate 45-working-hour inactivity countdown. The customer's next reply resumes the deadlines. The assigned agent can also **Mark resolved** and confirm the resolution.

Customers can reopen either closure outcome for seven calendar days from closure. Reopening starts a fresh SLA cycle at the ticket's current priority. The ticket goes back to its previous owner when that account is active, or to the unassigned queue. Staff can expand **Previous SLA cycles** to see earlier outcomes. A resolution without a public staff reply records the missing first response as **Not applicable** if its deadline was still pending, or **Late** if it was missed.

Run the worker alongside Flask to check for inactivity closures and record overdue milestones. It checks every 30 seconds by default and uses the actual inactivity cutoff as the closure time. Omit `--watch` to run one check.

```powershell
.\.venv\Scripts\python.exe -m flask --app app ticket-lifecycle --watch
```

## Dashboards, reports, and notifications

The ticket dashboard shows counts and status filters within the selected ticket scope. Customers can use **Needs your reply** to find their tickets waiting on them. Managers and admins use **Reports** to review first-response and resolution misses, open each ticket's audit history, and see resolved and inactivity-closed outcomes.

Report dates are inclusive in IST. Misses use the date of the missed deadline. Closures count each SLA cycle ending in the period, with reopening counted when a later cycle exists. Notification totals use the date each message was queued.

New public staff replies queue one email containing the ticket number and a portal link. The customer signs in to follow the link. Configure the `FRONTDESK_PUBLIC_URL` and `FRONTDESK_SMTP_*` values from `.env.example` to deliver the queued emails. Use `starttls` or `ssl` for an external mail server. Plain SMTP is reserved for loopback tests.

```powershell
.\.venv\Scripts\python.exe -m flask --app app notification-worker --watch
```

The outbox retains queued notifications until delivery is configured and the worker is running. **Sent** means the SMTP server accepted the message. Delivery confirmation requires a receipt from the mail provider. Failed and uncertain attempts are recorded for review.
