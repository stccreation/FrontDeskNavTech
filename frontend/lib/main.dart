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

class _FrontdeskAppState extends State<FrontdeskApp>
    with WidgetsBindingObserver {
  static const _verificationPrefix = 'verify=';
  final _navigator = GlobalKey<NavigatorState>();
  late final AuthApi _api = widget.api ?? AuthApi();
  late final TicketApi _tickets = TicketApi(_api.client);
  late final StaffApi _staff = StaffApi(_api.client);
  late final HolidayApi _holidays = HolidayApi(_api.client);
  late final ReportsApi _reports = ReportsApi(_api.client);
  int? _linkedTicket = int.tryParse(Uri.base.queryParameters['ticket'] ?? '');
  String? _verificationToken;
  Account? _account;
  String? _error;
  bool _loading = true;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final token = _tokenFromRoute(Uri.base.fragment);
    _verificationToken = token;
    if (token != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _verificationToken == token) {
          _preserveVerificationLink(token);
        }
      });
    }
    _restoreSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _api.close();
    super.dispose();
  }

  String? _tokenFromRoute(String path) => path.startsWith(_verificationPrefix)
      ? path.substring(_verificationPrefix.length)
      : null;

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final token = _tokenFromRoute(routeInformation.uri.path);
    if (token == null) return false;
    _navigator.currentState?.popUntil((route) => route.isFirst);
    setState(() => _verificationToken = token);
    _preserveVerificationLink(token);
    return true;
  }

  void _preserveVerificationLink(String token) {
    SystemNavigator.routeInformationUpdated(
      uri: Uri(path: '$_verificationPrefix$token'),
      replace: true,
    );
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

    final token = _verificationToken;
    return _CredentialsForm(
      key: ValueKey(token),
      api: _api,
      verificationToken: token,
      onCancelVerification: token == null ? null : () => _finishVerification(),
      onSignedIn: (account) {
        if (token == null) {
          setState(() => _account = account);
        } else {
          _finishVerification(account);
        }
      },
    );
  }

  void _finishVerification([Account? account]) {
    SystemNavigator.routeInformationUpdated(uri: Uri(path: '/'), replace: true);
    setState(() {
      _verificationToken = null;
      _account = account ?? _account;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frontdesk',
      debugShowCheckedModeBanner: false,
      theme: frontdeskTheme(),
      navigatorKey: _navigator,
      initialRoute: '/',
      home: _home(),
    );
  }

  Widget _home() {
    final account = _account;
    if (account == null || _verificationToken != null) return _entryPage();
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
    backgroundColor: deskPaper,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 840;
          final form = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
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
              Expanded(
                flex: 10,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: const _EntryBanner(compact: false),
                  ),
                ),
              ),
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
        height: 112,
        child: Stack(
          children: [
            const Positioned(
              right: -10,
              width: 108,
              top: -5,
              bottom: -5,
              child: TicketArtwork(),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DeskBrand(dark: true),
                    SizedBox(height: 8),
                    Text(
                      'Mon–Fri · 09:30–18:30 IST',
                      style: TextStyle(color: deskRailText, fontSize: 12),
                    ),
                  ],
                ),
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
  const _CredentialsForm({
    super.key,
    required this.api,
    required this.onSignedIn,
    this.verificationToken,
    this.onCancelVerification,
  });

  final AuthApi api;
  final ValueChanged<Account> onSignedIn;
  final String? verificationToken;
  final VoidCallback? onCancelVerification;

  @override
  State<_CredentialsForm> createState() => _CredentialsFormState();
}

class _CredentialsFormState extends State<_CredentialsForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _verificationRequested = false;
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
      if (_registering) {
        await widget.api.register(_name.text, _email.text);
        if (mounted) setState(() => _verificationRequested = true);
        return;
      }
      final token = widget.verificationToken;
      final account = token == null
          ? await widget.api.signIn(_email.text, _password.text)
          : await widget.api.verifyEmail(token, _password.text);
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
    _form.currentState?.reset();
    _password.clear();
    setState(() {
      _registering = !_registering;
      _verificationRequested = false;
      _obscurePassword = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final verifying = widget.verificationToken != null;
    if (_verificationRequested) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: CircleAvatar(
              radius: 26,
              backgroundColor: deskMint,
              foregroundColor: deskInk,
              child: Icon(Icons.mark_email_unread_outlined),
            ),
          ),
          const SizedBox(height: 18),
          Text('Check your email', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          const Text(
            'If the address is eligible, a verification link will arrive shortly. Open the link to choose a password and finish creating your account.',
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _verificationRequested = false),
            child: const Text('Request another link'),
          ),
          TextButton(
            onPressed: _toggleMode,
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              verifying
                  ? 'Verify your email'
                  : _registering
                  ? 'Create a customer account'
                  : 'Sign in',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              verifying
                  ? 'Choose a password to finish creating your account.'
                  : _registering
                  ? 'We’ll email you a link to finish creating your account.'
                  : 'Use your Frontdesk email and password.',
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
                  prefixIcon: Icon(Icons.person_outline),
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value!.trim().isEmpty ? 'Enter your name.' : null,
              ),
              const SizedBox(height: 12),
            ],
            if (!verifying)
              TextFormField(
                controller: _email,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: _registering
                    ? TextInputAction.done
                    : TextInputAction.next,
                onFieldSubmitted: _registering ? (_) => _submit() : null,
                autocorrect: false,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.mail_outline),
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value!.trim().isEmpty ? 'Enter your email address.' : null,
              ),
            if (!_registering) ...[
              if (!verifying) const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                enabled: !_submitting,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: [
                  verifying
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  labelText: verifying ? 'New password' : 'Password',
                  border: const OutlineInputBorder(),
                  helperText: verifying ? 'Use 15 to 128 characters.' : null,
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value!.isEmpty) return 'Enter your password.';
                  if (verifying &&
                      (value.runes.length < 15 || value.runes.length > 128)) {
                    return 'Use 15 to 128 characters.';
                  }
                  return null;
                },
              ),
            ],
            if (error != null) _ErrorMessage(error),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting
                    ? 'Please wait…'
                    : verifying
                    ? 'Verify email and sign in'
                    : _registering
                    ? 'Send verification link'
                    : 'Sign in',
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _submitting
                  ? null
                  : (widget.onCancelVerification ?? _toggleMode),
              child: Text(
                verifying || _registering
                    ? 'Back to sign in'
                    : 'Create a customer account',
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
