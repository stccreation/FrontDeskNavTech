import 'api_client.dart';

class StaffMember {
  StaffMember.fromJson(Map<String, dynamic> data)
    : id = data['id'] as int,
      name = data['name'] as String,
      email = data['email'] as String,
      isActive = data['is_active'] as bool,
      managerId = data['manager_id'] as int?,
      managerName = data['manager_name'] as String?,
      managerActive = data['manager_active'] as bool?;

  final int id;
  final String name;
  final String email;
  final bool isActive;
  final int? managerId;
  final String? managerName;
  final bool? managerActive;
}

class StaffRoster {
  StaffRoster.fromJson(Map<String, dynamic> data)
    : managers = _members(data['managers']),
      agents = _members(data['agents']);

  final List<StaffMember> managers;
  final List<StaffMember> agents;

  static List<StaffMember> _members(Object? value) => (value as List<dynamic>)
      .map((member) => StaffMember.fromJson(member as Map<String, dynamic>))
      .toList();
}

class StaffApi {
  StaffApi(this._client);

  final ApiClient _client;

  Future<StaffRoster> list() async =>
      StaffRoster.fromJson(await _client.get('/api/staff'));

  Future<void> add({
    required String name,
    required String email,
    required String role,
    required String temporaryPassword,
    int? managerId,
  }) async {
    await _client.post('/api/staff', {
      'name': name,
      'email': email,
      'role': role,
      'temporary_password': temporaryPassword,
      'manager_id': ?managerId,
    });
  }

  Future<void> move(StaffMember agent, int managerId) async {
    await _client.post('/api/staff/${agent.id}/manager', {
      'manager_id': managerId,
      'expected_manager_id': agent.managerId,
    });
  }
}
