import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontdesk/auth_api.dart';
import 'package:frontdesk/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final ticket = {
    'id': 42,
    'subject': 'Unable to open invoice',
    'priority': 'urgent',
    'status': 'open',
    'created_at': '2026-11-20T04:00:00Z',
    'customer_name': 'Anu',
    'owner_name': 'Ravi',
    'customer_blocked': true,
    'sla': {
      'first_response': {
        'status': 'overdue',
        'deadline': '2026-11-20T06:00:00Z',
      },
      'resolution': {'status': 'overdue', 'deadline': '2026-11-20T13:00:00Z'},
    },
  };

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('Agent queue and conversation at ${width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AuthApi(
        client: MockClient((request) async {
          final payload = switch (request.url.path) {
            '/api/auth/session' => {
              'user': {
                'name': 'Ravi',
                'email': 'agent@example.com',
                'role': 'agent',
              },
              'csrf_token': 'test',
            },
            '/api/tickets' => {
              'tickets': [ticket],
              'summary': {'all': 1, 'overdue': 1},
            },
            '/api/tickets/42' => {
              'ticket': ticket,
              'actions': {'reply': true, 'note': true, 'reply_and_wait': true},
              'messages': <Object>[],
            },
            _ => throw StateError(request.url.path),
          };
          return http.Response(jsonEncode(payload), 200);
        }),
      );
      await tester.pumpWidget(FrontdeskApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Reply overdue'), findsOneWidget);
      expect(find.text('Resolution overdue'), findsOneWidget);
      expect(
        find.text('Service deadline'),
        width >= 1040 ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('Unable to open invoice'));
      await tester.pumpAndSettle();
      expect(find.text('Conversation'), findsOneWidget);
      if (width < 920) {
        expect(find.text('SLA deadlines'), findsNothing);
        await tester.tap(find.text('Ticket details'));
        await tester.pumpAndSettle();
        expect(find.text('SLA deadlines'), findsOneWidget);
        await tester.tap(find.text('Ticket details'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Visible to the customer'), findsOneWidget);
      await tester.ensureVisible(find.text('Private note').first);
      await tester.tap(find.text('Private note').first);
      await tester.pumpAndSettle();
      expect(find.text('Only your team can see this note'), findsOneWidget);
      expect(find.text('Send reply'), findsNothing);
    });
  }
}
