import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontdesk/auth_api.dart';
import 'package:frontdesk/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Registration requests email verification before sign-in', (
    tester,
  ) async {
    final api = AuthApi(
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/session':
            return http.Response(
              jsonEncode({'user': null, 'csrf_token': 'guest'}),
              200,
            );
          case '/api/auth/register':
            expect(request.headers['X-CSRF-Token'], 'guest');
            expect(jsonDecode(request.body), {
              'name': 'Sample Customer',
              'email': 'customer@example.com',
            });
            return http.Response(
              jsonEncode({'verification_requested': true}),
              202,
            );
          case '/api/auth/login':
            expect(request.headers['X-CSRF-Token'], 'guest');
            expect(jsonDecode(request.body), {
              'email': 'customer@example.com',
              'password': 'a long passphrase',
            });
            return http.Response(
              jsonEncode({
                'user': {
                  'name': 'Sample Customer',
                  'email': 'customer@example.com',
                  'role': 'customer',
                },
                'csrf_token': 'signed-in',
              }),
              200,
            );
          case '/api/tickets':
            expect(request.url.queryParameters['scope'], 'mine');
            return http.Response(
              jsonEncode({'tickets': [], 'next_before': null}),
              200,
            );
          case '/api/auth/logout':
            expect(request.headers['X-CSRF-Token'], 'signed-in');
            return http.Response(
              jsonEncode({'user': null, 'csrf_token': 'new-guest'}),
              200,
            );
          default:
            throw StateError('Unexpected request to ${request.url.path}');
        }
      }),
    );

    await tester.pumpWidget(FrontdeskApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a customer account'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Sample Customer');
    await tester.enterText(fields.at(1), 'customer@example.com');
    await tester.ensureVisible(find.text('Send verification link'));
    await tester.tap(find.text('Send verification link'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('My tickets'), findsNothing);
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(0), 'customer@example.com');
    await tester.enterText(fields.at(1), 'a long passphrase');
    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Sample Customer · Customer'), findsOneWidget);
    expect(find.text('My tickets'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Create a customer account'), findsOneWidget);
  });

  testWidgets('Opens verification from an already open tab', (tester) async {
    final api = AuthApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/session');
        return http.Response(
          jsonEncode({'user': null, 'csrf_token': 'guest'}),
          200,
        );
      }),
    );

    await tester.pumpWidget(FrontdeskApp(api: api));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

    expect(await tester.binding.handlePushRoute('verify=${'A' * 43}'), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
  });
}
