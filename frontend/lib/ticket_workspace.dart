import 'package:flutter/material.dart';

import 'api_client.dart';
import 'auth_api.dart';
import 'frontdesk_design.dart';
import 'holiday_calendar.dart';
import 'reports_page.dart';
import 'staff_api.dart';
import 'staff_management.dart';
import 'ticket_api.dart';
import 'ticket_detail_page.dart';
import 'ticket_forms.dart';
import 'ticket_ui.dart';

class TicketWorkspace extends StatefulWidget {
  const TicketWorkspace({
    super.key,
    required this.account,
    required this.api,
    required this.staffApi,
    required this.holidayApi,
    required this.reportsApi,
    required this.onSignOut,
    required this.signingOut,
    this.signOutError,
    this.initialTicketId,
    this.onTicketLinkOpened,
  });

  final Account account;
  final TicketApi api;
  final StaffApi staffApi;
  final HolidayApi holidayApi;
  final ReportsApi reportsApi;
  final int? initialTicketId;
  final VoidCallback? onTicketLinkOpened;
  final VoidCallback onSignOut;
  final bool signingOut;
  final String? signOutError;

  @override
  State<TicketWorkspace> createState() => _TicketWorkspaceState();
}

class _TicketWorkspaceState extends State<TicketWorkspace> {
  late String _scope = widget.account.isCustomer ? 'mine' : 'queue';
  List<Ticket> _tickets = [];
  Map<String, int> _summary = const {};
  String _filter = 'all';
  int? _nextBefore;
  int _loadNumber = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    final linked = widget.initialTicketId;
    if (linked != null && linked > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onTicketLinkOpened?.call();
        _open(linked);
      });
    }
  }

  Future<void> _load({bool append = false}) async {
    final loadNumber = ++_loadNumber;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.list(
        _scope,
        filter: _filter,
        before: append ? _nextBefore : null,
      );
      if (!mounted || loadNumber != _loadNumber) return;
      setState(() {
        _tickets = append ? [..._tickets, ...page.tickets] : page.tickets;
        _nextBefore = page.nextBefore;
        _summary = page.summary;
      });
    } on ApiException catch (error) {
      if (mounted && loadNumber == _loadNumber) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && loadNumber == _loadNumber) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectScope(String scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _filter = 'all';
      _tickets = [];
      _summary = const {};
      _nextBefore = null;
    });
    _load();
  }

  void _selectFilter(String filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _tickets = [];
      _nextBefore = null;
    });
    _load();
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TicketDetailPage(id: id, account: widget.account, api: widget.api),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final id = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewTicketDialog(api: widget.api),
    );
    if (mounted && id != null) await _open(id);
  }

  String _section = 'tickets';

  void _navigate(String section, {String? scope}) {
    final previous = _section;
    setState(() => _section = section);
    if (scope != null && scope != _scope) {
      _selectScope(scope);
    } else if (section == 'tickets' && previous != section) {
      _load();
    }
  }

  Widget _navigation({required bool drawer}) {
    final account = widget.account;
    Widget item(String label, IconData icon, String section, {String? scope}) {
      final active = section == _section && (scope == null || scope == _scope);
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          selected: active,
          textColor: deskRailText,
          iconColor: deskRailText,
          selectedColor: deskInk,
          selectedTileColor: deskMint,
          leading: Icon(icon, size: 19),
          horizontalTitleGap: 10,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            label,
            style: TextStyle(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          onTap: () {
            if (drawer) Navigator.of(context).pop();
            _navigate(section, scope: scope);
          },
        ),
      );
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 8, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFADCBBC),
          letterSpacing: .5,
        ),
      ),
    );
    return Material(
      color: deskRail,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 12, 22),
              child: DeskBrand(dark: true),
            ),
            const Divider(height: 1, color: Color(0xFF38564B)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  heading('Workspace'),
                  if (account.isCustomer)
                    item(
                      'My requests',
                      Icons.confirmation_number_outlined,
                      'tickets',
                      scope: 'mine',
                    )
                  else ...[
                    item(
                      'Unassigned',
                      Icons.inbox_outlined,
                      'tickets',
                      scope: 'queue',
                    ),
                    item(
                      'Assigned to me',
                      Icons.assignment_ind_outlined,
                      'tickets',
                      scope: 'mine',
                    ),
                    if (account.canManage)
                      item(
                        'All tickets',
                        Icons.layers_outlined,
                        'tickets',
                        scope: 'all',
                      ),
                  ],
                  if (account.canManage) ...[
                    heading('Management'),
                    item('Staff Management', Icons.groups_outlined, 'staff'),
                    item('Holidays', Icons.calendar_month_outlined, 'holidays'),
                    item('Reports', Icons.bar_chart_outlined, 'reports'),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF38564B)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: const Color(0xFF34574B),
                    foregroundColor: deskMint,
                    child: Text(
                      account.name
                          .trim()
                          .characters
                          .take(1)
                          .toString()
                          .toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          account.roleLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: deskRailText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final width = MediaQuery.sizeOf(context).width;
    final sidebar = width >= 1040;
    final workspace = switch (_section) {
      'staff' => StaffManagementPage(
        api: widget.staffApi,
        isAdmin: account.isAdmin,
      ),
      'holidays' => HolidayCalendarPage(api: widget.holidayApi),
      'reports' => ReportsPage(api: widget.reportsApi, onOpenTicket: _open),
      _ => _queue(context),
    };
    return PopScope(
      canPop: _section == 'tickets',
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _section != 'tickets') _navigate('tickets');
      },
      child: Scaffold(
        drawer: sidebar ? null : Drawer(child: _navigation(drawer: true)),
        body: Row(
          children: [
            if (sidebar) ...[
              SizedBox(width: 222, child: _navigation(drawer: false)),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
                      color: deskPaper,
                      padding: EdgeInsets.symmetric(
                        horizontal: sidebar ? 28 : 8,
                      ),
                      height: 60,
                      child: Row(
                        children: [
                          if (!sidebar)
                            Builder(
                              builder: (context) => IconButton(
                                tooltip: 'Open navigation',
                                icon: const Icon(Icons.menu),
                                onPressed: () =>
                                    Scaffold.of(context).openDrawer(),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              sidebar
                                  ? 'Arvo Systems  /  ${account.isCustomer ? 'Customer portal' : 'Support workspace'}'
                                  : 'Frontdesk',
                              style: const TextStyle(
                                color: deskInk,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!sidebar && width >= 650)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: width * .36,
                              ),
                              child: Text(
                                '${account.name} · ${account.roleLabel}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          TextButton.icon(
                            onPressed: widget.signingOut
                                ? null
                                : widget.onSignOut,
                            icon: const Icon(Icons.logout, size: 17),
                            label: Text(
                              widget.signingOut ? 'Signing out…' : 'Sign out',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (widget.signOutError case final error?)
                      TicketErrorText(error),
                    Expanded(child: workspace),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _queue(BuildContext context) {
    final account = widget.account;
    final title = account.isCustomer
        ? 'My tickets'
        : switch (_scope) {
            'mine' => 'Assigned to me',
            'all' => 'All tickets',
            _ => 'Unassigned queue',
          };
    final description = account.isCustomer
        ? 'Track your requests and reply to the support team.'
        : switch (_scope) {
            'mine' => 'Your conversations and upcoming deadlines.',
            'all' => 'Tickets and service deadlines across all teams.',
            _ => 'Claim a ticket to start a conversation.',
          };
    final filters = [
      ('all', 'All tickets', Icons.inbox_outlined, deskGreen),
      ('open', 'Open', Icons.forum_outlined, const Color(0xFF28657C)),
      (
        'waiting',
        account.isCustomer ? 'Needs your reply' : 'Waiting on customer',
        Icons.hourglass_empty,
        deskAmber,
      ),
      if (!account.isCustomer) ('overdue', 'Overdue', Icons.alarm, deskLate),
      if (_scope != 'queue') ('closed', 'Closed', Icons.task_alt, deskMuted),
    ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final inset = bounds.maxWidth < 600 ? 16.0 : 28.0;
        final width = bounds.maxWidth - 2 * inset;
        final table = width >= 760;
        final selected = filters.firstWhere((f) => f.$1 == _filter);
        final count = _summary[_filter];
        return CustomScrollView(
          key: PageStorageKey('queue-$_scope'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, inset, inset, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DeskPageHeading(
                      title,
                      description: description,
                      actions: [
                        if (account.isCustomer)
                          FilledButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('New ticket'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, bounds) {
                        final compact = bounds.maxWidth < 560;
                        return DeskTileGrid(
                          columns: compact ? 2 : filters.length,
                          children: [
                            for (final f in filters)
                              _StatusFilter(
                                label: f.$2,
                                count: _summary[f.$1],
                                icon: f.$3,
                                color: f.$4,
                                selected: _filter == f.$1,
                                compact: compact,
                                onTap: () => _selectFilter(f.$1),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 9,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _filter == 'all' ? 'Tickets' : selected.$2,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (count != null)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2EBE5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '$count',
                                      style: const TextStyle(
                                        color: deskGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _loading ? null : _load,
                          tooltip: 'Refresh tickets',
                          icon: const Icon(Icons.refresh, size: 20),
                        ),
                      ],
                    ),
                    if (_error case final error?) TicketErrorText(error),
                    const SizedBox(height: 8),
                    if (table && _tickets.isNotEmpty)
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFE7EDE9),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: deskMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          child: _TicketColumns(
                            subject: const Text('Ticket'),
                            status: const Text('Status & priority'),
                            deadline: account.isCustomer
                                ? null
                                : const Text('Service deadline'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_tickets.isEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                sliver: SliverToBoxAdapter(
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: 'Loading tickets',
                            ),
                          ),
                        )
                      : DeskEmptyState(
                          icon: _error == null
                              ? selected.$3
                              : Icons.cloud_off_outlined,
                          title: _error != null
                              ? 'Tickets could not be loaded'
                              : _filter == 'overdue'
                              ? 'No overdue tickets'
                              : _filter != 'all'
                              ? 'No tickets match this filter'
                              : _scope == 'queue'
                              ? 'No tickets waiting to be claimed'
                              : 'No tickets yet',
                          action: _error != null
                              ? TextButton(
                                  onPressed: _load,
                                  child: const Text('Try again'),
                                )
                              : _filter != 'all'
                              ? TextButton(
                                  onPressed: () => _selectFilter('all'),
                                  child: const Text('Show all tickets'),
                                )
                              : null,
                        ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                sliver: SliverList.builder(
                  itemCount: _tickets.length,
                  itemBuilder: (context, i) {
                    final t = _tickets[i];
                    return _TicketRow(
                      ticket: t,
                      staff: !account.isCustomer,
                      table: table,
                      last: i == _tickets.length - 1,
                      onTap: () => _open(t.id),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _nextBefore == null
                    ? const SizedBox.shrink()
                    : Center(
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => _load(append: true),
                          child: Text(
                            _loading ? 'Loading…' : 'Load older tickets',
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.compact,
    required this.onTap,
  });
  final String label;
  final int? count;
  final IconData icon;
  final Color color;
  final bool selected, compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? deskGreen : deskLine),
    );
    final value = Text(
      count?.toString() ?? '—',
      style: TextStyle(
        fontSize: compact ? 18 : 28,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: selected ? deskGreen : deskInk,
      ),
    );
    final symbol = Icon(icon, size: compact ? 17 : 21, color: color);
    final name = Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: compact ? 12 : 13,
        color: deskInk,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      label: '$label · ${count ?? '—'}',
      excludeSemantics: true,
      child: Material(
        color: selected ? const Color(0xFFE6F1E8) : deskPaper,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 14),
            child: compact
                ? ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 28),
                    child: Row(
                      children: [
                        symbol,
                        const SizedBox(width: 6),
                        Expanded(child: name),
                        const SizedBox(width: 3),
                        value,
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: value),
                          symbol,
                        ],
                      ),
                      const SizedBox(height: 8),
                      name,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// Keep the list headers aligned with their cells for both roles.
class _TicketColumns extends StatelessWidget {
  const _TicketColumns({
    required this.subject,
    required this.status,
    this.deadline,
    this.trailing,
  });
  final Widget subject, status;
  final Widget? deadline, trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 5, child: subject),
      const SizedBox(width: 16),
      Expanded(flex: 3, child: status),
      if (deadline != null) ...[
        const SizedBox(width: 12),
        Expanded(flex: 3, child: deadline!),
      ],
      SizedBox(width: 24, child: trailing),
    ],
  );
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.ticket,
    required this.staff,
    required this.table,
    required this.last,
    required this.onTap,
  });
  final Ticket ticket;
  final bool staff, table, last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final subject = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          [
            '#${t.id}',
            if (staff && t.customerName != null) t.customerName!,
            if (staff)
              t.ownerName ?? 'Unassigned'
            else
              ticketTime(context, t.createdAt),
          ].join('  ·  '),
          style: const TextStyle(fontSize: 12, color: deskMuted),
        ),
      ],
    );
    final status = TicketBadges(
      ticket: t,
      customerView: !staff,
      showOverdue: false,
    );
    final deadline = staff ? _QueueDeadline(ticket: t) : null;
    const arrow = Icon(Icons.chevron_right, size: 17, color: deskMuted);
    final radius = table
        ? BorderRadius.vertical(bottom: Radius.circular(last ? 12 : 0))
        : BorderRadius.circular(12);
    return Padding(
      padding: EdgeInsets.only(bottom: table ? 0 : 8),
      child: Material(
        color: deskPaper,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: table
                  ? const Border(bottom: BorderSide(color: deskLine))
                  : Border.all(color: deskLine),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: table
                ? _TicketColumns(
                    subject: subject,
                    status: status,
                    deadline: deadline,
                    trailing: arrow,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: subject),
                          arrow,
                        ],
                      ),
                      const SizedBox(height: 9),
                      status,
                      if (deadline != null) ...[
                        const SizedBox(height: 8),
                        deadline,
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _QueueDeadline extends StatelessWidget {
  const _QueueDeadline({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final timing = ticket.timing;
    if (timing == null) return const Text('—');
    final milestones = [
      ('Reply', timing.firstResponse),
      ('Resolution', timing.resolution),
    ];
    final pending =
        milestones
            .where((m) => m.$2.status == 'pending' || m.$2.status == 'overdue')
            .toList()
          ..sort((a, b) => a.$2.deadline.compareTo(b.$2.deadline));
    if (pending.isNotEmpty) {
      final overdue = pending.where((m) => m.$2.status == 'overdue');
      final shown = overdue.isEmpty ? pending.take(1) : overdue;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final milestone in shown) ...[
            Text(
              '${milestone.$1} ${milestone.$2.status == 'overdue' ? 'overdue' : 'due'}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: milestone.$2.status == 'overdue' ? deskLate : deskInk,
              ),
            ),
            Text(
              slaTime(context, milestone.$2.deadline),
              style: const TextStyle(fontSize: 12, color: deskMuted),
            ),
          ],
        ],
      );
    }
    if (ticket.status == 'waiting_on_customer') {
      return const Text('Clock paused', style: TextStyle(color: deskAmber));
    }
    return Text(
      'Resolution · ${timing.resolution.label}',
      style: TextStyle(
        color: timing.resolution.status == 'late' ? deskLate : deskMuted,
      ),
    );
  }
}
