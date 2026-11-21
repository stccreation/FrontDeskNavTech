import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

class PendingAttachment {
  const PendingAttachment(this.file, this.size);

  final XFile file;
  final int size;
}

const priorityLabels = {'low': 'Low', 'medium': 'Medium', 'urgent': 'Urgent'};

class SlaMilestone {
  SlaMilestone.fromJson(Map<String, dynamic> json)
    : deadline = DateTime.parse(json['deadline'] as String),
      completedAt = DateTime.tryParse(json['completed_at'] as String? ?? ''),
      status = json['status'] as String;

  final DateTime deadline;
  final DateTime? completedAt;
  final String status;

  String get label => switch (status) {
    'met' => 'Met',
    'late' => 'Late',
    'overdue' => 'Overdue',
    'paused' => 'Paused',
    'not_applicable' => 'Not applicable',
    _ => 'Pending',
  };
}

class TicketTiming {
  TicketTiming.fromJson(Map<String, dynamic> json)
    : cycleNumber = json['cycle_number'] as int? ?? 1,
      closureStatus = json['closure_status'] as String?,
      previousCycles = (json['previous_cycles'] as List<dynamic>? ?? [])
          .map((item) => TicketTiming.fromJson(item as Map<String, dynamic>))
          .toList(),
      firstResponse = SlaMilestone.fromJson(
        json['first_response'] as Map<String, dynamic>,
      ),
      resolution = SlaMilestone.fromJson(
        json['resolution'] as Map<String, dynamic>,
      );

  final SlaMilestone firstResponse;
  final SlaMilestone resolution;
  final int cycleNumber;
  final String? closureStatus;
  final List<TicketTiming> previousCycles;
}

class Ticket {
  Ticket.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      subject = json['subject'] as String,
      priority = json['priority'] as String,
      status = json['status'] as String,
      customerBlocked = json['customer_blocked'] as bool,
      createdAt = DateTime.parse(json['created_at'] as String),
      customerName = json['customer_name'] as String?,
      ownerName = json['owner_name'] as String?,
      ownerId = json['owner_id'] as int?,
      ownershipVersion = json['ownership_version'] as int?,
      waitingUntil = DateTime.tryParse(json['waiting_until'] as String? ?? ''),
      reopenUntil = DateTime.tryParse(json['reopen_until'] as String? ?? ''),
      timing = json['sla'] == null
          ? null
          : TicketTiming.fromJson(json['sla'] as Map<String, dynamic>);

  final int id;
  final String subject;
  final String priority;
  final String status;
  final bool customerBlocked;
  final DateTime createdAt;
  final String? customerName;
  final String? ownerName;
  final int? ownerId;
  final int? ownershipVersion;
  final DateTime? waitingUntil;
  final DateTime? reopenUntil;
  final TicketTiming? timing;

  String get statusLabel => switch (status) {
    'waiting_on_customer' => 'Waiting on customer',
    'resolved' => 'Resolved',
    'closed_inactivity' => 'Closed for inactivity',
    _ => 'Open',
  };

  String get priorityLabel => priorityLabels[priority] ?? 'Medium';
}

class TicketAttachment {
  TicketAttachment.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      filename = json['filename'] as String;

  final int id;
  final String filename;
}

class TicketMessage {
  TicketMessage.fromJson(Map<String, dynamic> json)
    : author = json['author_name'] as String,
      body = json['body'] as String,
      isPrivate = json['visibility'] == 'private',
      createdAt = DateTime.parse(json['created_at'] as String),
      attachments = (json['attachments'] as List<dynamic>? ?? [])
          .map(
            (item) => TicketAttachment.fromJson(item as Map<String, dynamic>),
          )
          .toList();

  final String author;
  final String body;
  final bool isPrivate;
  final DateTime createdAt;
  final List<TicketAttachment> attachments;
}

class TicketDetail {
  TicketDetail.fromJson(Map<String, dynamic> json)
    : ticket = Ticket.fromJson(json['ticket'] as Map<String, dynamic>),
      messages = (json['messages'] as List<dynamic>)
          .map((item) => TicketMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
      actions = Map<String, bool>.from(json['actions'] as Map);

  final Ticket ticket;
  final List<TicketMessage> messages;
  final Map<String, bool> actions;

  bool can(String action) => actions[action] == true;
}

class SupportAgent {
  SupportAgent.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      name = json['name'] as String,
      email = json['email'] as String;

  final int id;
  final String name;
  final String email;
}

class TicketApi {
  TicketApi(this._client);

  final ApiClient _client;

  Future<({List<Ticket> tickets, int? nextBefore, Map<String, int> summary})>
  list(String scope, {String filter = 'all', int? before}) async {
    final result = await _client.get(
      '/api/tickets',
      query: {
        'scope': scope,
        if (filter != 'all') 'filter': filter,
        if (before != null) 'before': '$before',
      },
    );
    return (
      tickets: (result['tickets'] as List<dynamic>)
          .map((item) => Ticket.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextBefore: result['next_before'] as int?,
      summary: Map<String, int>.from(result['summary'] as Map? ?? const {}),
    );
  }

  Future<TicketDetail> detail(int id) async =>
      TicketDetail.fromJson(await _client.get('/api/tickets/$id'));

  Future<int> create({
    required String subject,
    required String description,
    required bool blocked,
    List<PendingAttachment> attachments = const [],
  }) async {
    final result = await _submit('/api/tickets', {
      'subject': subject,
      'description': description,
      'customer_blocked': blocked,
    }, attachments);
    return result['id'] as int;
  }

  Future<List<SupportAgent>> agents() async {
    final result = await _client.get('/api/tickets/agents');
    return (result['agents'] as List<dynamic>)
        .map((item) => SupportAgent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> claim(Ticket ticket) async {
    await _client.post('/api/tickets/${ticket.id}/claim', {
      'ownership_version': ticket.ownershipVersion,
    });
  }

  Future<void> transfer(Ticket ticket, int agentId, String reason) async {
    await _client.post('/api/tickets/${ticket.id}/transfer', {
      'agent_id': agentId,
      'ownership_version': ticket.ownershipVersion,
      'reason': reason,
    });
  }

  Future<void> changePriority(Ticket ticket, String priority) async {
    await _client.post('/api/tickets/${ticket.id}/priority', {
      'priority': priority,
      'expected_priority': ticket.priority,
    });
  }

  Future<void> waitForCustomer(Ticket ticket) => _ownerAction(ticket, 'wait');

  Future<void> resolve(Ticket ticket) => _ownerAction(ticket, 'resolve');

  Future<void> _ownerAction(Ticket ticket, String action) async {
    await _client.post('/api/tickets/${ticket.id}/$action', {
      'ownership_version': ticket.ownershipVersion,
    });
  }

  Future<void> reopen(Ticket ticket) async {
    await _client.post('/api/tickets/${ticket.id}/reopen', {});
  }

  Future<void> reply(
    Ticket ticket,
    String body,
    List<PendingAttachment> files, {
    bool waitForCustomer = false,
  }) async {
    await _submit('/api/tickets/${ticket.id}/replies', {
      'body': body,
      if (waitForCustomer) 'wait_for_customer': true,
      if (ticket.ownershipVersion != null)
        'ownership_version': ticket.ownershipVersion,
    }, files);
  }

  Future<void> note(
    Ticket ticket,
    String body,
    List<PendingAttachment> files,
  ) async {
    await _submit('/api/tickets/${ticket.id}/notes', {'body': body}, files);
  }

  Future<Map<String, dynamic>> _submit(
    String path,
    Map<String, Object?> data,
    List<PendingAttachment> files,
  ) {
    if (files.isEmpty) return _client.post(path, data);
    return _client.postWithFiles(path, data, [
      for (final item in files)
        http.MultipartFile(
          'attachments',
          item.file.openRead(),
          item.size,
          filename: item.file.name,
        ),
    ]);
  }
}
