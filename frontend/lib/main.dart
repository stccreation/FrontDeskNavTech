import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'auth_api.dart';
import 'holiday_calendar.dart';
import 'frontdesk_design.dart';
import 'reports_page.dart';
import 'staff_api.dart';
import 'staff_password_form.dart';
import 'ticket_api.dart';
import 'ticket_workspace.dart';

void main() => runApp(const FrontdeskApp());

class FrontdeskApp extends StatefulWidget {
  const FrontdeskApp({super.key, this.api});

  final AuthApi? api;

  @override
  State<FrontdeskApp> createState() => _FrontdeskAppState();
}

class _FrontdeskAppState extends State<FrontdeskApp> {
  late final AuthApi _api = widget.api ?? AuthApi();
  late final TicketApi _tickets = TicketApi(_api.client);
  late final StaffApi _staff = StaffApi(_api.client);
  late final HolidayApi _holidays = HolidayApi(_api.client);
  late final ReportsApi _reports = ReportsApi(_api.client);
  int? _linkedTicket = int.tryParse(Uri.base.queryParameters['ticket'] ?? '');
  Account? _account;
  String? _error;
  bool _loading = true;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = await _api.loadSession();
      if (mounted) setState(() => _account = account);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      final account = await _api.signOut();
      if (mounted) setState(() => _account = account);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Widget _content() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading Frontdesk'),
      );
    }

    final error = _error;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ErrorMessage(error),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _restoreSession,
            child: const Text('Try again'),
          ),
        ],
      );
    }

    return _CredentialsForm(
      api: _api,
      onSignedIn: (account) => setState(() => _account = account),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frontdesk',
      debugShowCheckedModeBanner: false,
      theme: frontdeskTheme(),
      home: _home(),
    );
  }

  Widget _home() {
    final account = _account;
    if (account == null) return _entryPage();
    if (account.mustChangePassword) {
      return _entryPage(
        content: StaffPasswordForm(
          api: _api,
          onCompleted: (updated) => setState(() {
            _account = updated;
            _error = null;
          }),
          onSignOut: _signOut,
          signingOut: _signingOut,
          signOutError: _error,
        ),
      );
    }
    return TicketWorkspace(
      account: account,
      api: _tickets,
      staffApi: _staff,
      holidayApi: _holidays,
      reportsApi: _reports,
      initialTicketId: _linkedTicket,
      onTicketLinkOpened: () => _linkedTicket = null,
      onSignOut: _signOut,
      signingOut: _signingOut,
      signOutError: _error,
    );
  }

  Widget _entryPage({Widget? content}) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 840;
          final form = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: content ?? _content(),
          );
          if (!wide) {
            return ListView(
              children: [
                const _EntryBanner(compact: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 32),
                  child: Center(child: form),
                ),
              ],
            );
          }
          return Row(
            children: [
              const Expanded(flex: 10, child: _EntryBanner(compact: false)),
              Expanded(
                flex: 11,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: form,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _EntryBanner extends StatelessWidget {
  const _EntryBanner({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        color: deskInk,
        height: 118,
        child: Stack(
          children: [
            const Positioned(
              right: -10,
              width: 138,
              top: -5,
              bottom: -5,
              child: TicketArtwork(),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 24),
                child: DeskBrand(dark: true),
              ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: deskInk,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final inset = bounds.maxWidth > 550 ? 52.0 : 32.0;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: bounds.maxHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: inset, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const DeskBrand(dark: true),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 30),
                        const Text(
                          'Arvo Systems',
                          style: TextStyle(
                            color: deskMint,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Support portal',
                          style: TextStyle(
                            color: deskPaper,
                            fontSize: bounds.maxWidth > 550 ? 64 : 48,
                            letterSpacing: -2.8,
                            height: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: (bounds.maxHeight * .31).clamp(150.0, 305.0),
                          child: const TicketArtwork(),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(color: Color(0xFF3A5458)),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Icon(Icons.schedule, size: 17, color: deskMint),
                              Text(
                                'Support hours',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Mon–Fri   09:30–18:30 IST',
                                style: TextStyle(color: Color(0xFFCDDBD6)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CredentialsForm extends StatefulWidget {
  const _CredentialsForm({required this.api, required this.onSignedIn});

  final AuthApi api;
  final ValueChanged<Account> onSignedIn;

  @override
  State<_CredentialsForm> createState() => _CredentialsFormState();
}

class _CredentialsFormState extends State<_CredentialsForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final account = _registering
          ? await widget.api.register(_name.text, _email.text, _password.text)
          : await widget.api.signIn(_email.text, _password.text);
      if (mounted && account != null) {
        TextInput.finishAutofillContext();
        widget.onSignedIn(account);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toggleMode() {
    _form.currentState!.reset();
    _password.clear();
    setState(() {
      _registering = !_registering;
      _obscurePassword = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _registering ? 'Create a customer account' : 'Sign in',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              _registering
                  ? 'Track your requests and reply to the support team.'
                  : 'Enter your account details to open your workspace.',
              style: const TextStyle(color: deskMuted),
            ),
            const SizedBox(height: 24),
            if (_registering) ...[
              TextFormField(
                controller: _name,
                enabled: !_submitting,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value!.trim().isEmpty ? 'Enter your name.' : null,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              decoration: const InputDecoration(
                labelText: 'Email address',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value!.trim().isEmpty ? 'Enter your email address.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              enabled: !_submitting,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [
                _registering
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                helperText: _registering ? 'Use at least 15 characters.' : null,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) {
                if (value!.isEmpty) return 'Enter your password.';
                if (_registering && value.runes.length < 15) {
                  return 'Use at least 15 characters.';
                }
                return null;
              },
            ),
            if (error != null) _ErrorMessage(error),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting
                    ? 'Please wait…'
                    : _registering
                    ? 'Create account'
                    : 'Sign in',
              ),
            ),
            TextButton(
              onPressed: _submitting ? null : _toggleMode,
              child: Text(
                _registering ? 'Back to sign in' : 'Create a customer account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
