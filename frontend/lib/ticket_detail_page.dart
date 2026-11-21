import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'attachment_picker.dart';
import 'frontdesk_design.dart';
import 'auth_api.dart';
import 'ticket_api.dart';
import 'ticket_forms.dart';
import 'ticket_ui.dart';

class TicketDetailPage extends StatefulWidget {
  const TicketDetailPage({
    super.key,
    required this.id,
    required this.account,
    required this.api,
  });

  final int id;
  final Account account;
  final TicketApi api;

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  final _reply = TextEditingController();
  final _note = TextEditingController();
  List<PendingAttachment> _replyFiles = [];
  List<PendingAttachment> _noteFiles = [];
  TicketDetail? _detail;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _noteSelected = false;
  bool _waitForReply = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.detail(widget.id);
      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          if (error.status == 404) _detail = null;
          _error = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    if (_saving || _loading) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _send(
    Ticket ticket,
    bool privateNote, {
    bool wait = false,
  }) async {
    final draft = privateNote ? _note : _reply;
    final body = draft.text.trim();
    final files = privateNote ? _noteFiles : _replyFiles;
    if (body.isEmpty && files.isEmpty) {
      setState(
        () => _error = privateNote
            ? 'Enter a private note or attach a file.'
            : 'Enter a reply or attach a file.',
      );
      return;
    }
    await _save(() async {
      if (privateNote) {
        await widget.api.note(ticket, body, files);
      } else {
        await widget.api.reply(ticket, body, files, waitForCustomer: wait);
      }
      if (mounted) {
        draft.clear();
        setState(() {
          if (privateNote) {
            _noteFiles = [];
          } else {
            _replyFiles = [];
            _waitForReply = false;
          }
        });
      }
    });
  }

  Future<void> _resolve(Ticket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark ticket resolved?'),
        content: const Text(
          'Frontdesk will record the resolution time and open the seven-day reopening window.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm resolution'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await _save(() => widget.api.resolve(ticket));
    }
  }

  Future<void> _transfer(Ticket ticket) async {
    final result = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TransferTicketDialog(api: widget.api, ticket: ticket),
    );
    if (!mounted) return;
    if (result is String) {
      setState(() => _error = result);
    } else if (result == true) {
      if (widget.account.canManage) {
        await _load();
      } else {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _changePriority(Ticket ticket) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change priority'),
        children: [
          for (final entry in priorityLabels.entries)
            SimpleDialogOption(
              onPressed: entry.key == ticket.priority
                  ? null
                  : () => Navigator.pop(context, entry.key),
              child: Text(
                entry.key == ticket.priority
                    ? '${entry.value} (current)'
                    : entry.value,
              ),
            ),
        ],
      ),
    );
    if (mounted && selected != null) {
      await _save(() => widget.api.changePriority(ticket, selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final error = _error;
    final enabled = !_loading && !_saving;
    return Scaffold(
      backgroundColor: ticketPageColor,
      appBar: AppBar(
        title: Text('Ticket #${widget.id}'),
        actions: [
          IconButton(
            onPressed: enabled ? _load : null,
            tooltip: 'Refresh ticket',
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: detail == null
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator(
                            semanticsLabel: 'Loading ticket',
                          )
                        : TicketErrorText(
                            error ?? 'Unable to load the ticket.',
                          ),
                  )
                : _thread(context, detail, error: error, enabled: enabled),
          ),
        ),
      ),
    );
  }

  Widget _thread(
    BuildContext context,
    TicketDetail detail, {
    String? error,
    required bool enabled,
  }) {
    final ticket = detail.ticket;
    final isStaff = !widget.account.isCustomer;
    final theme = Theme.of(context);
    final canReopen = detail.can('reopen');
    final canReply = detail.can('reply') || canReopen;
    final canNote = detail.can('note');
    final privateNote = canNote && (_noteSelected || !canReply);

    final mayWait = !privateNote && detail.can('reply_and_wait');
    final sendingAndWaiting = mayWait && _waitForReply;
    final info = <Widget>[
      Text('Ticket details', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      TicketBadges(ticket: ticket),
      const SizedBox(height: 8),
      Text(ticketTime(context, ticket.createdAt)),
      if (isStaff) ...[
        const SizedBox(height: 8),
        Text('Customer: ${ticket.customerName}'),
        Text('Assigned to: ${ticket.ownerName ?? 'Unassigned'}'),
        if (ticket.customerBlocked) const Text('Customer reported blocked'),
        if (detail.can('claim') ||
            detail.can('transfer') ||
            detail.can('priority') ||
            detail.can('resolve') ||
            detail.can('wait')) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (detail.can('claim'))
                FilledButton(
                  onPressed: enabled
                      ? () => _save(() => widget.api.claim(ticket))
                      : null,
                  child: const Text('Claim ticket'),
                ),
              if (detail.can('transfer'))
                OutlinedButton(
                  onPressed: enabled ? () => _transfer(ticket) : null,
                  child: Text(
                    ticket.ownerId == null
                        ? 'Assign ticket'
                        : 'Transfer ticket',
                  ),
                ),
              if (detail.can('priority'))
                OutlinedButton(
                  onPressed: enabled ? () => _changePriority(ticket) : null,
                  child: const Text('Change priority'),
                ),
              if (detail.can('wait'))
                OutlinedButton(
                  onPressed: enabled
                      ? () => _save(() => widget.api.waitForCustomer(ticket))
                      : null,
                  child: const Text('Waiting on customer'),
                ),
              if (detail.can('resolve'))
                OutlinedButton(
                  onPressed: enabled ? () => _resolve(ticket) : null,
                  child: const Text('Mark resolved'),
                ),
            ],
          ),
        ],
      ],
      if (ticket.waitingUntil case final waitingUntil?) ...[
        const SizedBox(height: 8),
        Text('Closes for inactivity ${slaTime(context, waitingUntil)}'),
      ],
      if (!isStaff && ticket.reopenUntil != null) ...[
        const SizedBox(height: 12),
        if (canReopen) ...[
          Text('Reopen by ${slaTime(context, ticket.reopenUntil!)}'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: enabled
                  ? () => _save(() => widget.api.reopen(ticket))
                  : null,
              child: const Text('Reopen ticket'),
            ),
          ),
        ] else
          const Text(
            'Open a new ticket to continue. The reopening window has ended.',
          ),
      ],
      if (error != null) TicketErrorText(error),
      if (ticket.timing case final timing?) ...[
        const SizedBox(height: 18),
        TicketTimingPanel(timing: timing),
        if (timing.previousCycles.isNotEmpty)
          ExpansionTile(
            title: const Text('Previous SLA cycles'),
            children: [
              for (final previous in timing.previousCycles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TicketTimingPanel(
                    timing: previous,
                    title:
                        'Cycle ${previous.cycleNumber} · ${previous.closureStatus == 'resolved' ? 'Resolved' : 'Closed for inactivity'}',
                  ),
                ),
            ],
          ),
      ],
    ];
    final conversation = <Widget>[
      Text('Conversation', style: theme.textTheme.titleLarge),
      const SizedBox(height: 10),
      for (final message in detail.messages)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MessageCard(ticketId: ticket.id, message: message),
        ),
      if (canReply || canNote) ...[
        const SizedBox(height: 12),
        Card(
          semanticContainer: false,
          margin: EdgeInsets.zero,
          color: privateNote ? const Color(0xFFFFF6E3) : deskPaper,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canReply && canNote) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Public reply'),
                        ),
                        ButtonSegment(value: true, label: Text('Private note')),
                      ],
                      selected: {privateNote},
                      onSelectionChanged: enabled
                          ? (selection) => setState(() {
                              _noteSelected = selection.single;
                              _waitForReply = false;
                              _error = null;
                            })
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: ValueKey(privateNote),
                  controller: privateNote ? _note : _reply,
                  enabled: enabled,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 8000,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: privateNote
                        ? const Color(0xFFFFF8E7)
                        : Colors.white,
                    labelText: privateNote
                        ? 'Private note'
                        : (isStaff ? 'Reply to customer' : 'Your reply'),
                    helperText: privateNote ? 'Visible to staff only.' : null,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                AttachmentPicker(
                  key: ValueKey('attachments-$privateNote'),
                  files: privateNote ? _noteFiles : _replyFiles,
                  enabled: enabled,
                  onChanged: (files) => setState(() {
                    if (privateNote) {
                      _noteFiles = files;
                    } else {
                      _replyFiles = files;
                    }
                  }),
                ),
                const SizedBox(height: 10),
                if (mayWait)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _waitForReply,
                    title: const Text('Wait for customer reply'),
                    onChanged: enabled
                        ? (value) =>
                              setState(() => _waitForReply = value ?? false)
                        : null,
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: Icon(
                      privateNote ? Icons.lock_outline : Icons.send_outlined,
                      size: 17,
                    ),
                    onPressed: enabled
                        ? () => _send(
                            ticket,
                            privateNote,
                            wait: sendingAndWaiting,
                          )
                        : null,
                    label: Text(
                      privateNote
                          ? 'Add private note'
                          : canReopen
                          ? 'Reopen and reply'
                          : sendingAndWaiting
                          ? 'Send reply and wait'
                          : 'Send reply',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 920;
        final summary = Card(
          semanticContainer: false,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: info,
            ),
          ),
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 24, wide ? 32 : 16, 32),
          children: [
            Text(ticket.subject, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 18),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: conversation,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(flex: 4, child: summary),
                ],
              )
            else ...[
              summary,
              const SizedBox(height: 20),
              ...conversation,
            ],
          ],
        );
      },
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.ticketId, required this.message});

  final int ticketId;
  final TicketMessage message;

  Future<void> _download(
    BuildContext context,
    TicketAttachment attachment,
  ) async {
    final location = Uri.base.resolve(
      '/api/tickets/$ticketId/attachments/${attachment.id}',
    );
    final opened = await launchUrl(location, webOnlyWindowName: '_self');
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to download the attachment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: message.isPrivate ? const Color(0xFFFFF4D9) : Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              Icon(
                message.isPrivate
                    ? Icons.lock_outline
                    : Icons.chat_bubble_outline,
                color: message.isPrivate ? const Color(0xFF825712) : deskGreen,
                size: 17,
              ),
              Text(
                message.author,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (message.isPrivate)
                const Text(
                  'Private note',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              Text(ticketTime(context, message.createdAt)),
            ],
          ),
          if (message.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(message.body),
          ],
          if (message.attachments.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final attachment in message.attachments)
                  TextButton.icon(
                    onPressed: () => _download(context, attachment),
                    icon: const Icon(Icons.download_outlined),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 210),
                      child: Text(
                        attachment.filename,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
