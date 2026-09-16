import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khata_clone_app/core/api_client.dart';
import 'package:khata_clone_app/core/lang.dart';
import 'package:khata_clone_app/core/state.dart';
import 'package:khata_clone_app/features/vault/vault_config.dart';
import 'package:khata_clone_app/features/vault/vault_state.dart';
import 'package:khata_clone_app/main.dart';

Widget _pumpApp(ApiClient api, AuthState auth) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider(create: (_) => VaultState()),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider(create: (_) => KhataState(api)),
      ChangeNotifierProvider(create: (_) => BookState(api)),
      ChangeNotifierProvider(create: (_) => BillState(api)),
      ChangeNotifierProvider(create: (_) => CollectionState(api)),
      ChangeNotifierProvider(create: (_) => RecycleState(api)),
      ChangeNotifierProvider(create: (_) => ExpenseState(api)),
      ChangeNotifierProvider(create: (_) => ItemState(api)),
      ChangeNotifierProvider(create: (_) => DashboardState(api)),
      ChangeNotifierProvider(create: (_) => BusinessState(api)),
      ChangeNotifierProvider(create: (_) => LanguageState()),
    ],
    child: const KhataApp(),
  );
}

/// Types the debug vault code on the disguise calculator and presses `=`.
/// Digits are tapped in an order that keeps every lookup unambiguous with
/// the live display (the display only ever shows the full entry string).
Future<void> _unlockCalculator(WidgetTester tester) async {
  for (final d in VaultConfig.code.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
  await tester.tap(find.text('='));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Cold start shows only the disguise calculator', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1');
    await tester.pumpWidget(_pumpApp(api, AuthState(api)..init()));
    await tester.pumpAndSettle();
    // Calculator keys visible, real app nowhere in sight.
    expect(find.text('='), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('English'), findsNothing);
    expect(find.text('हिन्दी'), findsNothing);
  });

  testWidgets('Wrong code just computes, vault stays locked', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1');
    await tester.pumpWidget(_pumpApp(api, AuthState(api)..init()));
    await tester.pumpAndSettle();
    for (final k in ['1', '2', '+', '3', '=']) {
      await tester.tap(find.text(k));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    // 12+3 computed normally and the disguise is still up.
    expect(find.text('15'), findsOneWidget);
    expect(find.text('English'), findsNothing);
  });

  testWidgets('Vault code reveals the app: language first, then phone login', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1');
    await tester.pumpWidget(_pumpApp(api, AuthState(api)..init()));
    await tester.pumpAndSettle();
    await _unlockCalculator(tester);
    // First run: language picker (English / हिन्दी), no assumed default.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('हिन्दी'), findsOneWidget);
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    // Choice applied: Hindi phone login follows.
    expect(find.text('अपने मोबाइल नंबर से लॉगिन करें'), findsOneWidget);
  });

  testWidgets('Phone continue routes to password entry', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1');
    final auth = AuthState(api);
    await tester.pumpWidget(_pumpApp(api, auth));
    await auth.init(); // unreachable backend → falls back to phone stage
    await tester.pump();
    await _unlockCalculator(tester);
    // Pick a language first (first-run gate), then the phone stage shows.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(auth.stage, AuthStage.phone);
    expect(auth.goToPassword('123'), isFalse); // invalid phone rejected
    expect(auth.goToPassword('9876543210'), isTrue);
    await tester.pumpAndSettle();
    expect(auth.stage, AuthStage.password);
    expect(find.text('Login'), findsWidgets);
  });
}
