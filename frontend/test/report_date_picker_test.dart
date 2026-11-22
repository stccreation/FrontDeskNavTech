import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontdesk/api_client.dart';
import 'package:frontdesk/frontdesk_design.dart';
import 'package:frontdesk/reports_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final size in [const Size(1366, 768), const Size(320, 640)]) {
    testWidgets('Report dates open in a compact dialog at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final requests = <Map<String, String>>[];
      final client = ApiClient(
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          requests.add(query);
          return http.Response(
            jsonEncode({
              'period': {
                'from': query['from'] ?? '2026-11-01',
                'to': query['to'] ?? '2026-11-22',
                'today': '2026-11-22',
              },
              'misses': {'first_response': 0, 'resolution': 0},
              'closures': {
                'resolved': {'count': 0, 'reopened': 0},
                'closed_inactivity': {'count': 0, 'reopened': 0},
              },
              'notifications': {'queued': 0, 'sent': 0, 'failed': 0},
              'tickets': [],
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: frontdeskTheme(),
          home: ReportsPage(api: ReportsApi(client), onOpenTicket: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      final filter = find.widgetWithIcon(
        OutlinedButton,
        Icons.date_range_outlined,
      );
      await tester.tap(filter);
      await tester.pumpAndSettle();
      final sizeOfDialog = tester.getSize(find.byType(Dialog));
      expect(sizeOfDialog.width, lessThanOrEqualTo(460));
      expect(sizeOfDialog.width, lessThan(size.width));
      expect(sizeOfDialog.height, lessThanOrEqualTo(560));
      expect(sizeOfDialog.height, lessThan(size.height));

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));

      await tester.tap(filter);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '11/10/2026');
      await tester.enterText(find.byType(TextField).at(1), '11/15/2026');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(requests.last, {'from': '2026-11-10', 'to': '2026-11-15'});
      expect(find.byType(DateRangePickerDialog), findsNothing);
    });
  }
}
