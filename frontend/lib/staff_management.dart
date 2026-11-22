import 'package:flutter/material.dart';

import 'api_client.dart';
import 'staff_api.dart';
import 'ticket_ui.dart';
import 'frontdesk_design.dart';

class StaffManagementPage extends StatefulWidget {
  const StaffManagementPage({
    super.key,
    required this.api,
    required this.isAdmin,
  });

  final StaffApi api;
  final bool isAdmin;

  @override
  State<StaffManagementPage> createState() => _StaffManagementPageState();
}

class _StaffManagementPageState extends State<StaffManagementPage> {
  StaffRoster? _roster;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roster = await widget.api.list();
      if (mounted) setState(() => _roster = roster);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({StaffMember? agent}) async {
    final roster = _roster;
    if (roster == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StaffEditor(
        api: widget.api,
        isAdmin: widget.isAdmin,
        managers: roster.managers.where((manager) => manager.isActive).toList(),
        agent: agent,
      ),
    );
    if (mounted && saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    final error = _error;
    return Scaffold(
      backgroundColor: ticketPageColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                DeskPageHeading(
                  widget.isAdmin ? 'Staff management' : 'My team',
                  description: widget.isAdmin
                      ? 'Manage team members and their reporting assignments.'
                      : 'Manage the support agents assigned to you.',
                  actions: [
                    IconButton(
                      tooltip: 'Refresh staff',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                      onPressed: _loading || roster == null
                          ? null
                          : () => _edit(),
                      label: Text(
                        widget.isAdmin ? 'Add staff' : 'Add support agent',
                      ),
                    ),
                  ],
                ),
                if (error != null) TicketErrorText(error),
                if (_loading && roster == null) ...[
                  const SizedBox(height: 32),
                  const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading staff',
                    ),
                  ),
                ],
                if (roster != null) ...[
                  if (widget.isAdmin) ...[
                    const SizedBox(height: 24),
                    _section('Managers', roster.managers, isAgent: false),
                  ],
                  const SizedBox(height: 24),
                  _section('Support agents', roster.agents, isAgent: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    String label,
    List<StaffMember> members, {
    required bool isAgent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label (${members.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          DeskEmptyState(
            icon: Icons.groups_outlined,
            title: isAgent ? 'No support agents yet' : 'No managers yet',
          ),
        for (final member in members)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.white,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isAgent
                    ? const Color(0xFFE8EFE2)
                    : const Color(0xFFDDECEB),
                foregroundColor: deskInk,
                child: Text(
                  member.name
                      .trim()
                      .characters
                      .take(1)
                      .toString()
                      .toUpperCase(),
                ),
              ),
              title: Text(
                member.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.email),
                  if (widget.isAdmin && isAgent)
                    Text(
                      member.managerId == null
                          ? 'Unassigned'
                          : 'Manager: ${member.managerName}${member.managerActive == false ? ' (inactive)' : ''}',
                    ),
                  if (!member.isActive) const Text('Inactive'),
                ],
              ),
              trailing: widget.isAdmin && isAgent
                  ? TextButton(
                      onPressed: _loading ? null : () => _edit(agent: member),
                      child: Text(member.managerId == null ? 'Assign' : 'Move'),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _StaffEditor extends StatefulWidget {
  const _StaffEditor({
    required this.api,
    required this.isAdmin,
    required this.managers,
    this.agent,
  });

  final StaffApi api;
  final bool isAdmin;
  final List<StaffMember> managers;
  final StaffMember? agent;

  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _temporaryPassword = TextEditingController();
  String _role = 'agent';
  int? _managerId;
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _temporaryPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final agent = widget.agent;
      if (agent == null) {
        await widget.api.add(
          name: _name.text,
          email: _email.text,
          role: _role,
          temporaryPassword: _temporaryPassword.text,
          managerId: _managerId,
        );
      } else {
        await widget.api.move(agent, _managerId!);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final moving = agent != null;
    final showManagers = moving || widget.isAdmin && _role == 'agent';
    final availableManagers = widget.managers
        .where((manager) => manager.id != agent?.managerId)
        .toList();
    final title = moving
        ? (agent.managerId == null
              ? 'Assign manager'
              : 'Move to another manager')
        : (widget.isAdmin ? 'Add staff' : 'Add support agent');
    final error = _error;

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(title),
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (moving) ...[
                  Text(
                    agent.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  if (widget.isAdmin) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      items: const [
                        DropdownMenuItem(
                          value: 'agent',
                          child: Text('Support agent'),
                        ),
                        DropdownMenuItem(
                          value: 'manager',
                          child: Text('Manager'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _saving
                          ? null
                          : (role) => setState(() {
                              _role = role ?? 'agent';
                              _managerId = null;
                            }),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value!.trim().isEmpty ? 'Enter a name.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    enabled: !_saving,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value!.trim().isEmpty
                        ? 'Enter an email address.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _temporaryPassword,
                    enabled: !_saving,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Temporary password',
                      helperText: '15 to 128 characters',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value!.runes.length < 15 || value.runes.length > 128
                        ? 'Use 15 to 128 characters.'
                        : null,
                  ),
                ],
                if (showManagers && !moving) const SizedBox(height: 12),
                if (showManagers)
                  DropdownButtonFormField<int>(
                    initialValue: _managerId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Active manager',
                      helperText: availableManagers.isEmpty
                          ? (moving
                                ? 'No other active managers are available.'
                                : 'Create a manager first.')
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final manager in availableManagers)
                        DropdownMenuItem(
                          value: manager.id,
                          child: Text(
                            '${manager.name} · ${manager.email}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving || availableManagers.isEmpty
                        ? null
                        : (value) => _managerId = value,
                    validator: (value) =>
                        value == null ? 'Choose an active manager.' : null,
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
            onPressed: _saving || (showManagers && availableManagers.isEmpty)
                ? null
                : _submit,
            child: Text(
              _saving
                  ? 'Saving…'
                  : (moving ? 'Save assignment' : 'Create account'),
            ),
          ),
        ],
      ),
    );
  }
}
