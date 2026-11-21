import 'package:flutter/material.dart';

import 'ticket_api.dart';
import 'frontdesk_design.dart';

const ticketPageColor = deskCanvas;

String ticketTime(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatMediumDate(local)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String slaTime(BuildContext context, DateTime timestamp) {
  final indiaTime = timestamp.toUtc().add(
    const Duration(hours: 5, minutes: 30),
  );
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatMediumDate(indiaTime)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(indiaTime))} IST';
}

class TicketTimingPanel extends StatelessWidget {
  const TicketTimingPanel({
    super.key,
    required this.timing,
    this.title = 'SLA deadlines',
  });

  final TicketTiming timing;
  final String title;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _milestone(context, 'First response', timing.firstResponse),
          const Divider(height: 20),
          _milestone(context, 'Resolution', timing.resolution),
        ],
      ),
    ),
  );

  Widget _milestone(
    BuildContext context,
    String title,
    SlaMilestone milestone,
  ) {
    final completedAt = milestone.completedAt;
    final late = milestone.status == 'overdue' || milestone.status == 'late';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              milestone.label,
              style: TextStyle(
                color: late ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ],
        ),
        if (milestone.status != 'paused')
          Text('Due ${slaTime(context, milestone.deadline)}'),
        if (completedAt != null)
          Text('Completed ${slaTime(context, completedAt)}'),
      ],
    );
  }
}

class TicketBadges extends StatelessWidget {
  const TicketBadges({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (statusFill, statusInk) = switch (ticket.status) {
      'waiting_on_customer' => (
        const Color(0xFFFFEBCC),
        const Color(0xFF794800),
      ),
      'resolved' => (const Color(0xFFDCECCF), const Color(0xFF36532B)),
      'closed_inactivity' => (const Color(0xFFE8E8E3), const Color(0xFF525750)),
      _ => (const Color(0xFFDBEFED), const Color(0xFF235955)),
    };
    final urgent = ticket.priority == 'urgent';
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _badge(ticket.statusLabel, statusFill, statusInk),
        _badge(
          ticket.priorityLabel,
          urgent ? colors.errorContainer : colors.surfaceContainerHighest,
          urgent ? colors.onErrorContainer : colors.onSurfaceVariant,
        ),
        if (ticket.timing?.firstResponse.status == 'overdue')
          _badge(
            'Response overdue',
            colors.errorContainer,
            colors.onErrorContainer,
          ),
        if (ticket.timing?.resolution.status == 'overdue')
          _badge(
            'Resolution overdue',
            colors.errorContainer,
            colors.onErrorContainer,
          ),
      ],
    );
  }

  Widget _badge(String text, Color background, Color foreground) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

class TicketErrorText extends StatelessWidget {
  const TicketErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
