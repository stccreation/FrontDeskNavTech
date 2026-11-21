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
          selectedColor: deskInk,
          selectedTileColor: const Color(0xFFDEEDCF),
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
          color: deskMuted,
        ),
      ),
    );
    return Material(
      color: deskPaper,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 12, 22),
              child: DeskBrand(),
            ),
            const Divider(height: 1),
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.account_circle_outlined, color: deskMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          account.roleLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: deskMuted,
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
                                  ? 'Arvo Systems  /  Support'
                                  : 'Frontdesk',
                              style: const TextStyle(
                                color: deskInk,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!sidebar && width >= 650)
                            Flexible(
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
        ? 'Follow your requests and reply to the support team.'
        : switch (_scope) {
            'mine' => 'Your active conversations and service deadlines.',
            'all' => 'Review tickets and deadlines across all teams.',
            _ => 'Claim a ticket to start helping a customer.',
          };
    final filters = [
      ('all', 'All statuses', Icons.layers_outlined, deskGreen),
      ('open', 'Open', Icons.radio_button_checked, const Color(0xFF28657C)),
      (
        'waiting',
        account.isCustomer ? 'Needs your reply' : 'Waiting on customer',
        Icons.hourglass_empty,
        const Color(0xFF86601E),
      ),
      if (!account.isCustomer)
        ('overdue', 'Overdue', Icons.alarm, const Color(0xFFAC483B)),
      if (_scope != 'queue') ('closed', 'Closed', Icons.task_alt, deskMuted),
    ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final small = bounds.maxWidth < 620;
        final padding = small ? 16.0 : 28.0;
        return CustomScrollView(
          key: PageStorageKey('queue-$_scope'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: deskInk,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          if (!small)
                            const Positioned(
                              top: -10,
                              bottom: -20,
                              right: -10,
                              width: 250,
                              child: TicketArtwork(),
                            ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              small ? 18 : 28,
                              24,
                              small ? 18 : 228,
                              24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium!
                                      .copyWith(
                                        color: deskPaper,
                                        fontSize: small ? 27 : 34,
                                      ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  description,
                                  style: const TextStyle(
                                    color: Color(0xFFD8E1DA),
                                    fontSize: 14,
                                  ),
                                ),
                                if (account.isCustomer) ...[
                                  const SizedBox(height: 15),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: deskMint,
                                      foregroundColor: deskInk,
                                    ),
                                    onPressed: _create,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('New ticket'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, metrics) {
                        final columns = small
                            ? 2
                            : metrics.maxWidth / filters.length < 122
                            ? 3
                            : filters.length;
                        return Column(
                          children: [
                            for (
                              int start = 0;
                              start < filters.length;
                              start += columns
                            )
                              Padding(
                                padding: EdgeInsets.only(
                                  top: start == 0 ? 0 : 8,
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final f
                                          in filters
                                              .skip(start)
                                              .take(columns)) ...[
                                        if (f != filters[start])
                                          const SizedBox(width: 8),
                                        Expanded(
                                          child: _StatusFilter(
                                            label: f.$2,
                                            count: _summary[f.$1],
                                            icon: f.$3,
                                            color: f.$4,
                                            selected: _filter == f.$1,
                                            compact: small,
                                            onTap: () => _selectFilter(f.$1),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ticket list',
                            style: Theme.of(context).textTheme.titleLarge,
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
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            if (_tickets.isEmpty)
              SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverToBoxAdapter(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: 'Loading tickets',
                          ),
                        )
                      : Column(
                          children: [
                            const CircleAvatar(
                              radius: 25,
                              backgroundColor: Color(0xFFE5EBDD),
                              child: Icon(
                                Icons.inbox_outlined,
                                color: deskGreen,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error != null
                                  ? 'Use Refresh tickets to try again.'
                                  : 'No tickets in this view.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                sliver: SliverList.builder(
                  itemCount: _tickets.length,
                  itemBuilder: (context, index) {
                    final t = _tickets[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TicketRow(
                        ticket: t,
                        staff: !account.isCustomer,
                        onTap: () => _open(t.id),
                      ),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
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
      side: BorderSide(
        color: selected ? deskGreen : deskLine,
        width: selected ? 1.5 : 1,
      ),
    );
    return Semantics(
      button: true,
      onTap: onTap,
      selected: selected,
      label: '$label · ${count ?? '—'}',
      excludeSemantics: true,
      child: Material(
        color: selected ? const Color(0xFFEAF2E4) : deskPaper,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 11 : 14),
            child: compact
                ? Row(
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        count?.toString() ?? '—',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 18, color: color),
                          const Spacer(),
                          Text(
                            count?.toString() ?? '—',
                            style: TextStyle(
                              fontSize: compact ? 20 : 25,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: deskInk,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: deskMuted,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.ticket,
    required this.staff,
    required this.onTap,
  });
  final Ticket ticket;
  final bool staff;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final badges = TicketBadges(ticket: t);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final wide = bounds.maxWidth >= 740;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${t.id}  ·  ${ticketTime(context, t.createdAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: deskMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    t.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (staff)
                    Text(
                      [
                        if (t.customerName != null) t.customerName!,
                        t.ownerName ?? 'Unassigned',
                      ].join('  ·  '),
                      style: const TextStyle(color: deskMuted, fontSize: 13),
                    ),
                  if (!wide) ...[const SizedBox(height: 8), badges],
                ],
              );
              return Row(
                children: [
                  Expanded(child: info),
                  if (wide) ...[
                    const SizedBox(width: 8),
                    SizedBox(width: 250, child: badges),
                  ],
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 18, color: deskMuted),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
