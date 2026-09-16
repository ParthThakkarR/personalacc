import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khata_clone_app/core/api_client.dart';
import 'package:khata_clone_app/core/lang.dart';
import 'package:khata_clone_app/core/state.dart';
import 'package:khata_clone_app/main.dart';

void main() {
  testWidgets('Khata app asks language first, then shows phone login', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider(create: (_) => AuthState(api)..init()),
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
      ),
    );
    await tester.pumpAndSettle();
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
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
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
      ),
    );
    await auth.init(); // unreachable backend → falls back to phone stage
    await tester.pumpAndSettle();
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
