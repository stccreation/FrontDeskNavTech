import 'package:flutter/material.dart';

import 'api_client.dart';
import 'ticket_ui.dart';
import 'frontdesk_design.dart';
import 'report_charts.dart';

String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;

class ClosureTotal {
  ClosureTotal.fromJson(Map<String, dynamic> data)
    : count = data['count'] as int,
      reopened = data['reopened'] as int;

  final int count;
  final int reopened;
}

class MissedDeadline {
  MissedDeadline.fromJson(Map<String, dynamic> data)
    : ticketId = data['ticket_id'] as int,
      subject = data['subject'] as String,
      cycle = data['cycle_number'] as int,
      milestone = data['milestone'] as String,
      closureStatus = data['closure_status'] as String?,
      deadline = DateTime.parse(data['deadline_at'] as String),
      completed = DateTime.tryParse(data['completed_at'] as String? ?? '');

  final int ticketId;
  final String subject;
  final int cycle;
  final String milestone;
  final String? closureStatus;
  final DateTime deadline;
  final DateTime? completed;

  String get milestoneLabel =>
      milestone == 'first_response' ? 'First response' : 'Resolution';
}

class SlaReport {
  SlaReport.fromJson(Map<String, dynamic> data)
    : period = DateTimeRange(
        start: DateTime.parse(data['period']['from'] as String),
        end: DateTime.parse(data['period']['to'] as String),
      ),
      today = DateTime.parse(data['period']['today'] as String),
      missed = Map<String, int>.from(data['misses'] as Map),
      resolved = ClosureTotal.fromJson(
        data['closures']['resolved'] as Map<String, dynamic>,
      ),
      inactive = ClosureTotal.fromJson(
        data['closures']['closed_inactivity'] as Map<String, dynamic>,
      ),
      intervalDays = data['closure_activity']?['interval_days'] as int? ?? 1,
      buckets =
          (data['closure_activity']?['buckets'] as List<dynamic>? ?? const [])
              .map(
                (item) => ClosureBucket.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      leaderboard = (data['leaderboard'] as List<dynamic>? ?? const [])
          .map((item) => ResolverTotal.fromJson(item as Map<String, dynamic>))
          .toList(),
      notifications = Map<String, dynamic>.from(data['notifications'] as Map),
      rows = (data['tickets'] as List<dynamic>)
          .map((row) => MissedDeadline.fromJson(row as Map<String, dynamic>))
          .toList(),
      nextOffset = data['next_offset'] as int?;

  final DateTimeRange period;
  final DateTime today;
  final Map<String, int> missed;
  final ClosureTotal resolved;
  final ClosureTotal inactive;
  final int intervalDays;
  final List<ClosureBucket> buckets;
  final List<ResolverTotal> leaderboard;
  final Map<String, dynamic> notifications;
  final List<MissedDeadline> rows;
  final int? nextOffset;
}

class TicketHistoryEvent {
  TicketHistoryEvent.fromJson(Map<String, dynamic> data)
    : occurredAt = DateTime.parse(data['occurred_at'] as String),
      action = data['action'] as String,
      actor = data['actor_name'] as String? ?? 'System',
      details = Map<String, dynamic>.from(data['details'] as Map);

  final DateTime occurredAt;
  final String action;
  final String actor;
  final Map<String, dynamic> details;
}

class ReportsApi {
  const ReportsApi(this._client);

  final ApiClient _client;

  Future<SlaReport> load({
    DateTimeRange? period,
    required String milestone,
    int? offset,
  }) async {
    final response = await _client.get(
      '/api/reports/sla',
      query: {
        if (period != null) 'from': _dateOnly(period.start),
        if (period != null) 'to': _dateOnly(period.end),
        if (milestone != 'all') 'milestone': milestone,
        if (offset != null) 'offset': '$offset',
      },
    );
    return SlaReport.fromJson(response);
  }

  Future<({List<TicketHistoryEvent> events, int? nextBefore})> history(
    int id, {
    int? before,
  }) async {
    final response = await _client.get(
      '/api/reports/tickets/$id/history',
      query: {if (before != null) 'before': '$before'},
    );
    return (
      events: (response['events'] as List<dynamic>)
          .map(
            (item) => TicketHistoryEvent.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      nextBefore: response['next_before'] as int?,
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.api, required this.onOpenTicket});

  final ReportsApi api;
  final ValueChanged<int> onOpenTicket;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  SlaReport? _report;
  List<MissedDeadline> _rows = [];
  DateTimeRange? _period;
  String _milestone = 'all';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.api.load(
        period: _period,
        milestone: _milestone,
        offset: append ? _report?.nextOffset : null,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _rows = append ? [..._rows, ...report.rows] : report.rows;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDates(SlaReport report) async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(report.today.year - 10),
      lastDate: report.today,
      initialDateRange: report.period,
    );
    if (!mounted || selected == null) return;
    if (selected.end.difference(selected.start).inDays >= 366) {
      setState(() => _error = 'Choose a period of up to 366 days.');
      return;
    }
    _period = selected;
    await _load();
  }

  void _openHistory(MissedDeadline row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TicketHistoryPage(
          row: row,
          api: widget.api,
          openTicket: () => widget.onOpenTicket(row.ticketId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final error = _error;
    final theme = Theme.of(context);
    final locale = MaterialLocalizations.of(context);
    return Scaffold(
      backgroundColor: ticketPageColor,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              DeskPageHeading(
                'SLA reports',
                description:
                    'Ticket outcomes, service deadlines and staff resolutions.',
                actions: [
                  IconButton(
                    onPressed: _loading ? null : _load,
                    tooltip: 'Refresh reports',
                    icon: const Icon(Icons.refresh),
                  ),
                  if (report != null)
                    OutlinedButton.icon(
                      onPressed: _loading ? null : () => _chooseDates(report),
                      icon: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(
                        '${locale.formatShortDate(report.period.start)} – ${locale.formatShortDate(report.period.end)}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (error != null) TicketErrorText(error),
              if (report == null && _loading)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading reports',
                  ),
                ),
              if (report != null) ...[
                LayoutBuilder(
                  builder: (context, bounds) => DeskTileGrid(
                    columns: bounds.maxWidth >= 720 ? 4 : 2,
                    children: [
                      _Metric(
                        label: 'Resolved cycles',
                        value: report.resolved.count,
                        icon: Icons.task_alt,
                        tint: deskGreen,
                      ),
                      _Metric(
                        label: 'Closed for inactivity',
                        value: report.inactive.count,
                        icon: Icons.hourglass_bottom,
                        tint: deskAmber,
                      ),
                      _Metric(
                        label: 'Reply deadlines missed',
                        value: report.missed['first_response'] ?? 0,
                        icon: Icons.mark_chat_unread_outlined,
                        tint: deskLate,
                      ),
                      _Metric(
                        label: 'Resolution deadlines missed',
                        value: report.missed['resolution'] ?? 0,
                        icon: Icons.timer_off_outlined,
                        tint: deskLate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, bounds) {
                    final chart = ClosureActivityChart(
                      key: ValueKey(('activity', report.period)),
                      buckets: report.buckets,
                      intervalDays: report.intervalDays,
                    );
                    final leaderboard = ResolutionLeaderboard(
                      key: ValueKey(('leaderboard', report.period)),
                      entries: report.leaderboard,
                    );
                    if (bounds.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 16,
                        children: [
                          Expanded(flex: 3, child: chart),
                          Expanded(flex: 2, child: leaderboard),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 16,
                      children: [chart, leaderboard],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('Ticket closures', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _ClosureCard(
                  resolved: report.resolved,
                  inactive: report.inactive,
                ),
                const SizedBox(height: 24),
                Text('Missed deadlines', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final filter in const {
                      'all': 'All milestones',
                      'first_response': 'First response',
                      'resolution': 'Resolution',
                    }.entries)
                      ChoiceChip(
                        label: Text(filter.value),
                        selected: _milestone == filter.key,
                        onSelected: _loading
                            ? null
                            : (_) {
                                if (_milestone == filter.key) return;
                                setState(() {
                                  _milestone = filter.key;
                                  _rows = [];
                                });
                                _load();
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_rows.isEmpty && !_loading && error == null)
                  const DeskEmptyState(
                    icon: Icons.task_alt,
                    title: 'No missed deadlines in this view',
                  ),
                if (_loading && _rows.isEmpty) const LinearProgressIndicator(),
                for (final row in _rows)
                  Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('#${row.ticketId} · ${row.subject}'),
                      subtitle: Text(
                        [
                          '${row.milestoneLabel} · Cycle ${row.cycle}',
                          'Due ${slaTime(context, row.deadline)}',
                          if (row.completed != null)
                            'Completed ${slaTime(context, row.completed!)}'
                          else if (row.closureStatus == 'closed_inactivity')
                            'Closed for inactivity'
                          else if (row.closureStatus == 'resolved')
                            'Closed without this milestone'
                          else
                            'Awaiting completion',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.history),
                      onTap: () => _openHistory(row),
                    ),
                  ),
                if (report.nextOffset != null)
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : () => _load(append: true),
                      child: const Text('Load more missed deadlines'),
                    ),
                  ),
                const SizedBox(height: 24),
                Text('Reply notifications', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  report.notifications['delivery_configured'] == true
                      ? 'Sent emails have been accepted by the mail server.'
                      : 'SMTP setup is pending. Reply notifications are queued.',
                  style: const TextStyle(color: deskMuted),
                ),
                const SizedBox(height: 10),
                DeskTileGrid(
                  columns: 3,
                  children: [
                    for (final status in const {
                      'queued': 'Queued',
                      'sent': 'Sent',
                      'failed': 'Failed',
                    }.entries)
                      _Metric(
                        label: status.value,
                        value: report.notifications[status.key] as int,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.icon,
    this.tint = deskGreen,
  });

  final String label;
  final int value;
  final IconData? icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatDecimal(value),
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: tint),
                ),
              ),
              if (icon != null)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: tint.withValues(alpha: .09),
                  foregroundColor: tint,
                  child: Icon(icon, size: 17),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _ClosureCard extends StatelessWidget {
  const _ClosureCard({required this.resolved, required this.inactive});

  final ClosureTotal resolved;
  final ClosureTotal inactive;

  @override
  Widget build(BuildContext context) {
    final total = resolved.count + inactive.count;
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _closureRow('Resolved', resolved, total),
            const SizedBox(height: 16),
            _closureRow('Closed for inactivity', inactive, total),
          ],
        ),
      ),
    );
  }

  Widget _closureRow(String label, ClosureTotal closure, int total) {
    final fraction = total == 0 ? 0.0 : closure.count / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          '${closure.count} of $total closures · ${(fraction * 100).toStringAsFixed(1)}% · ${closure.reopened} reopened',
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          borderRadius: BorderRadius.circular(5),
          minHeight: 6,
          color: label == 'Resolved' ? deskGreen : const Color(0xFFA46C33),
          backgroundColor: const Color(0xFFE7EDE9),
          value: fraction,
          semanticsLabel: '$label share of closures',
        ),
      ],
    );
  }
}

class _TicketHistoryPage extends StatefulWidget {
  const _TicketHistoryPage({
    required this.row,
    required this.api,
    required this.openTicket,
  });

  final MissedDeadline row;
  final ReportsApi api;
  final VoidCallback openTicket;

  @override
  State<_TicketHistoryPage> createState() => _TicketHistoryPageState();
}

class _TicketHistoryPageState extends State<_TicketHistoryPage> {
  List<TicketHistoryEvent> _events = [];
  int? _nextBefore;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.history(
        widget.row.ticketId,
        before: append ? _nextBefore : null,
      );
      if (mounted) {
        setState(() {
          _events = append ? [..._events, ...page.events] : page.events;
          _nextBefore = page.nextBefore;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final error = _error;
    return Scaffold(
      backgroundColor: ticketPageColor,
      appBar: AppBar(
        title: Text('Ticket #${row.ticketId} history'),
        actions: [
          TextButton(
            onPressed: widget.openTicket,
            child: const Text('Open ticket'),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                row.subject,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${row.milestoneLabel} · Cycle ${row.cycle} · Due ${slaTime(context, row.deadline)}',
              ),
              const SizedBox(height: 14),
              if (error != null) ...[
                TicketErrorText(error),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
              if (_loading && _events.isEmpty) const LinearProgressIndicator(),
              for (final event in _events)
                Card(
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _auditLabel(event.action),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${event.actor} · ${slaTime(context, event.occurredAt)}',
                        ),
                        const SizedBox(height: 4),
                        for (final field in event.details.entries)
                          Text(
                            '${_auditLabel(field.key)} · ${_auditValue(context, field.value)}',
                          ),
                      ],
                    ),
                  ),
                ),
              if (_nextBefore != null)
                TextButton(
                  onPressed: _loading ? null : () => _load(append: true),
                  child: const Text('Load older events'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _auditLabel(String value) {
  final words = value.replaceAll('_', ' ');
  if (words.isEmpty) return words;
  if (words.startsWith('sla ')) return 'SLA ${words.substring(4)}';
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

String _auditValue(BuildContext context, Object? value) {
  if (value == null) return '—';
  if (value is Map) {
    return value.entries
        .map(
          (item) =>
              '${_auditLabel('${item.key}')} · ${_auditValue(context, item.value)}',
        )
        .join('\n');
  }
  if (value is String) {
    final date = value.endsWith('Z') ? DateTime.tryParse(value) : null;
    if (date != null) return slaTime(context, date);
    if (RegExp(r'^[a-z]+(?:_[a-z]+)+$').hasMatch(value)) {
      return _auditLabel(value);
    }
  }
  return '$value';
}
