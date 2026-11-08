import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:email_client/main.dart';
import 'package:email_client/state/email_client_state.dart';

void main() {
  testWidgets('App renders 3 columns: Inbox, AI-Spam, and Spam', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final state = EmailClientState(autoConnect: false);
    await tester.pumpWidget(EmailClientApp(state: state));

    expect(find.byType(EmailClientApp), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('AI-Spam'), findsOneWidget);
    expect(find.text('Spam'), findsOneWidget);

    // Verify Recheck buttons exist next to refresh in each column header
    expect(find.byTooltip('Recheck Inbox with retrained profile'), findsOneWidget);
    expect(find.byTooltip('Recheck AI-Spam with retrained profile'), findsOneWidget);
    expect(find.byTooltip('Recheck Spam with retrained profile'), findsOneWidget);
  });
}
