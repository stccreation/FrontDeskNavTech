import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'auth_api.dart';
import 'ticket_ui.dart';

class StaffPasswordForm extends StatefulWidget {
  const StaffPasswordForm({
    super.key,
    required this.api,
    required this.onCompleted,
    required this.onSignOut,
    required this.signingOut,
    this.signOutError,
  });

  final AuthApi api;
  final ValueChanged<Account> onCompleted;
  final VoidCallback onSignOut;
  final bool signingOut;
  final String? signOutError;

  @override
  State<StaffPasswordForm> createState() => _StaffPasswordFormState();
}

class _StaffPasswordFormState extends State<StaffPasswordForm> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || widget.signingOut || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = await widget.api.choosePassword(_password.text);
      if (mounted && account != null) {
        TextInput.finishAutofillContext();
        widget.onCompleted(account);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_saving && !widget.signingOut;
    final error = _error ?? widget.signOutError;

    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a permanent password',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: enabled,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: '15 to 128 characters',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value!.runes.length < 15 || value.runes.length > 128
                  ? 'Use 15 to 128 characters.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmation,
              enabled: enabled,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == _password.text ? null : 'The passwords must match.',
            ),
            if (error != null) TicketErrorText(error),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: enabled ? _save : null,
              child: Text(_saving ? 'Saving…' : 'Set password'),
            ),
            TextButton(
              onPressed: enabled ? widget.onSignOut : null,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
