# Frontdesk completion note

## Implemented

Frontdesk supports email-verified signup, staff accounts, ticket assignment and transfers, public replies, private notes, and attachments. The backend enforces access rules and prevents simultaneous claims from assigning the same ticket twice. Managers can manage holidays, review SLA misses and resolution counts, and inspect the append-only audit history.

## Decisions

- SLA deadlines count working hours in IST. Waiting for a customer pauses the applicable deadlines. After 45 working hours without a reply, the ticket closes for inactivity. Customers have seven calendar days from closure to reopen it.
- Urgent issues are due at the end of that working day if they arrive before closing. At closing time or on a non-working day, they are due at the next working day's close. The assessment left the late-arrival exception open, so an urgent issue arriving at 6:00 PM on a working day is due at 6:30 PM.

## Outstanding

- I deferred self-service password reset and replying to tickets by email to focus on ticket ownership, privacy, and SLA handling. Customers read and respond to replies in the portal.
- Reopened tickets return to the previous owner's active account when available. I deferred leave and shift scheduling to focus on staff accounts and ticket assignments.
- Attachments use disk storage on the application server. Shared storage and automated backups were deferred to keep the first release focused on a single server.

## Verification

Local tests covered signup through password setup and sign-in using MariaDB and an SMTP capture server. A verification email from the deployed portal also reached the test inbox.
