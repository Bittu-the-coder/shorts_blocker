import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shorts_blocker/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.experiment.shorts_blocker/service');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getDashboardData':
              return jsonEncode({
                'shortsCount': 2,
                'shortsLimit': 3,
                'wasteSeconds': 180,
                'productiveSeconds': 240,
                'neutralSeconds': 60,
                'isProtectionEnabled': true,
                'appUsage': [
                  {
                    'packageName': 'com.android.chrome',
                    'label': 'Chrome',
                    'category': 'neutral',
                    'seconds': 60,
                  },
                ],
              });
            case 'getRules':
              return jsonEncode([
                {
                  'packageName': 'com.android.chrome',
                  'label': 'Chrome',
                  'category': 'neutral',
                  'blockShorts': true,
                  'isPreset': true,
                },
              ]);
            case 'saveRules':
            case 'resetStats':
            case 'openAccessibilitySettings':
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('renders dashboard and rules', (tester) async {
    await tester.pumpWidget(const ShortsBlockerApp());
    await tester.pumpAndSettle();

    expect(find.text('Focus Guard'), findsOneWidget);
    expect(find.text('Browser and app protection is active'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Rules'), findsOneWidget);

    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();

    expect(find.text('Rule system'), findsOneWidget);
    expect(find.text('Add or update a rule'), findsOneWidget);
  });
}
