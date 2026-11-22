# Frontdesk completion note

## Implemented

Frontdesk includes email-verified signup, staff and team management, ticket conversations with attachments, a holiday calendar, and SLA reports with ticket history.

## Decisions

- **Ticket ownership (INC-0291).** A database row lock and ownership version let one claim or transfer succeed and reject stale requests. Only the current owner can send a public staff reply. The owner can transfer the ticket to an active agent, and managers and admins can reassign active tickets across teams. SLA deadlines follow the ticket through a transfer.
- **Private notes (INC-0304).** Public replies and team notes use separate actions. The backend filters notes and their attachments out of customer responses and checks access on every download. Reply emails contain the ticket number and a portal link.
- **Audit history (INC-0318).** An append-only log records the actor and server timestamp for replies, ownership changes, and SLA events. The first public staff reply determines the response time. Reports preserve past breaches and credit completed resolutions to the staff member who resolved each cycle.
- **Working calendar.** SLA time runs Monday to Friday, 9:30 AM to 6:30 PM IST, excluding configured holidays. Medium uses 4.5 working hours to reply and 27 to resolve. Low uses 9 and 45. Urgent uses two working hours to reply and the next working close to resolve. A 6:00 PM urgent arrival on a working day is due at 6:30 PM that day because a late-arrival exception was left open. Holiday edits adjust future working time and record any deadline changes.
- **Priority changes.** New tickets start at Medium, or Urgent when the customer reports they are blocked. On escalation, each pending milestone takes the earlier of its existing deadline and the deadline calculated at escalation. Downgrades preserve promised deadlines. Completed results and recorded breaches stay in history.
- **Waiting for the customer.** The assignee can pause after a public reply in the current cycle that follows the customer's latest message. A customer reply resumes the remaining working time. After 45 working hours of silence, the ticket is marked **Closed for inactivity**. An outstanding resolution is recorded as **Not applicable** unless a breach already occurred.
- **Reopening.** Customers have seven calendar days from either kind of closure. Reopening starts a fresh SLA cycle at the last priority and preserves earlier results. The ticket returns to the previous owner if their account is active, or goes back to the unassigned queue. After the window, the customer opens a new ticket.

## Outstanding

- I deferred self-service password reset and replying to tickets by email to focus on ticket ownership, privacy, and SLA handling. Customers read and respond to replies in the portal.
- I deferred leave and shift scheduling to focus on staff accounts and ticket assignments.
- Attachments use disk storage on the application server. Shared storage and automated backups were deferred to keep the first release focused on a single server.

## Verification

Local tests covered signup through password setup and sign-in using MariaDB and an SMTP capture server. A verification email from the deployed portal also reached the test inbox.
