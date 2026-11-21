# Frontdesk completion note

## Implemented

Frontdesk supports email-verified customer signup, staff accounts, ticket assignment and transfers, public replies, private notes, and attachments. The backend enforces access rules and prevents concurrent claims from assigning the same ticket twice. Managers can change holiday dates, review separate reply and resolution deadlines, and inspect the append-only audit history.

## Decisions

- SLA deadlines count working hours in IST. Waiting for a customer pauses the applicable deadlines. After 45 working hours without a reply, the ticket closes for inactivity. Customers have seven calendar days from closure to reopen it.
- I used end of the same working day for urgent issues received during office hours and end of the next working day for arrivals after closing or on a non-working day. This leaves a short resolution window for an urgent issue received late in the afternoon.

## Outstanding

- I deferred self-service password reset to focus on ticket ownership, privacy, and SLA handling.
- Uploads are stored on disk with access checks on downloads. Shared object storage and automated backups are outside this version.
- The deployed portal and database health check respond over HTTPS. The new signup flow was verified locally with MariaDB and an SMTP capture server. An end-to-end signup and inbox delivery test on the deployed instance is pending.
