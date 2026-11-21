import 'package:flutter/material.dart';

import 'api_client.dart';
import 'attachment_picker.dart';
import 'ticket_api.dart';
import 'ticket_ui.dart';

class NewTicketDialog extends StatefulWidget {
  const NewTicketDialog({super.key, required this.api});

  final TicketApi api;

  @override
  State<NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<NewTicketDialog> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  List<PendingAttachment> _attachments = [];
  bool _canWork = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.api.create(
        subject: _subject.text,
        description: _description.text,
        blocked: !_canWork,
        attachments: _attachments,
      );
      if (mounted) Navigator.pop(context, id);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('New ticket'),
        scrollable: true,
        content: SizedBox(
          width: 470,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _subject,
                  enabled: !_saving,
                  maxLength: 180,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Enter a subject.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  enabled: !_saving,
                  maxLength: 8000,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'What happened?',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                    counterText: '',
                  ),
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Describe the problem.' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<bool>(
                  initialValue: _canWork,
                  decoration: const InputDecoration(
                    labelText: 'Can you work at all?',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: true,
                      child: Text('Yes, I can work'),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text('No, I’m blocked'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => _canWork = value ?? true,
                ),
                const SizedBox(height: 8),
                AttachmentPicker(
                  files: _attachments,
                  enabled: !_saving,
                  onChanged: (files) => setState(() => _attachments = files),
                ),
                if (error != null) TicketErrorText(error),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Submitting…' : 'Submit ticket'),
          ),
        ],
      ),
    );
  }
}

class TransferTicketDialog extends StatefulWidget {
  const TransferTicketDialog({
    super.key,
    required this.api,
    required this.ticket,
  });

  final TicketApi api;
  final Ticket ticket;

  @override
  State<TransferTicketDialog> createState() => _TransferTicketDialogState();
}

class _TransferTicketDialogState extends State<TransferTicketDialog> {
  final _reason = TextEditingController();
  late final Future<List<SupportAgent>> _agents = widget.api.agents();
  int? _agentId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final agentId = _agentId;
    if (agentId == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.transfer(widget.ticket, agentId, _reason.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted && error.code == 'ownership_changed') {
        Navigator.pop(context, error.message);
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final label = widget.ticket.ownerId == null
        ? 'Assign ticket'
        : 'Transfer ticket';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(label),
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: FutureBuilder<List<SupportAgent>>(
            future: _agents,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading agents',
                  ),
                );
              }
              if (snapshot.hasError) {
                final problem = snapshot.error;
                return TicketErrorText(
                  problem is ApiException
                      ? problem.message
                      : 'Unable to load agents.',
                );
              }
              final agents = snapshot.data!
                  .where((agent) => agent.id != widget.ticket.ownerId)
                  .toList();
              if (agents.isEmpty) {
                return const Text('There are no other active agents.');
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _agentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Active agent',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final agent in agents)
                        DropdownMenuItem(
                          value: agent.id,
                          child: Text(
                            '${agent.name} · ${agent.email}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _agentId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reason,
                    enabled: !_saving,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  if (error != null) TicketErrorText(error),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || _agentId == null ? null : _submit,
            child: Text(_saving ? 'Saving…' : label),
          ),
        ],
      ),
    );
  }
}
