import 'package:http/http.dart' as http;

import 'api_client.dart';

class Account {
  const Account({
    required this.name,
    required this.email,
    required this.role,
    this.mustChangePassword = false,
  });

  factory Account.fromJson(Map<String, dynamic> data) => Account(
    name: data['name'] as String,
    email: data['email'] as String,
    role: data['role'] as String,
    mustChangePassword: data['must_change_password'] == true,
  );

  final String name;
  final String email;
  final String role;
  final bool mustChangePassword;

  bool get isCustomer => role == 'customer';
  bool get isAdmin => role == 'admin';
  bool get canManage => role == 'manager' || role == 'admin';

  String get roleLabel => switch (role) {
    'agent' => 'Support agent',
    'manager' => 'Manager',
    'admin' => 'Administrator',
    _ => 'Customer',
  };
}

class AuthApi {
  AuthApi({http.Client? client}) : client = ApiClient(client: client);

  final ApiClient client;

  Future<Account?> loadSession() async =>
      _session(await client.get('/api/auth/session'));

  Future<Account?> signIn(String email, String password) =>
      _post('login', {'email': email, 'password': password});

  Future<void> register(String name, String email) async {
    await client.post('/api/auth/register', {
      'name': name,
      'email': email,
    }, timeout: const Duration(seconds: 30));
  }

  Future<Account?> verifyEmail(String token, String password) =>
      _post('verify-email', {'token': token, 'password': password});

  Future<Account?> signOut() => _post('logout', {});

  Future<Account?> choosePassword(String password) =>
      _post('password', {'password': password});

  Future<Account?> _post(String action, Map<String, String> data) async =>
      _session(await client.post('/api/auth/$action', data));

  Account? _session(Map<String, dynamic> payload) {
    try {
      client.csrfToken = payload['csrf_token'] as String;
      final user = payload['user'] as Map<String, dynamic>?;
      return user == null ? null : Account.fromJson(user);
    } on TypeError {
      throw const ApiException('Frontdesk returned an unexpected session.');
    }
  }

  void close() => client.close();
}
