import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/lang.dart';
import 'core/state.dart';
import 'features/vault/calculator_screen.dart';
import 'features/vault/vault_state.dart';
import 'features/auth/phone_screen.dart';
import 'features/auth/language_screen.dart';
// OTP seam (PARKED): re-enable with AuthStage.otp case below + AuthState OTP
// methods when the SMS provider is funded.
// import 'features/auth/otp_screen.dart';
import 'features/auth/password_screen.dart';
import 'features/auth/profile_setup_screen.dart';
import 'features/auth/pin_setup_screen.dart';
import 'features/auth/pin_unlock_screen.dart';
import 'features/home/home_screen.dart';

void main() {
  final api = ApiClient();
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => VaultState()),
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
}

class KhataApp extends StatelessWidget {
  const KhataApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Disguise name: launcher, recents screen and task switcher all show
      // "Calculator". The real app only appears after the vault code.
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B3A)),
        useMaterial3: true,
      ),
      home: const VaultShield(),
    );
  }
}

/// Vault gate: cold start always shows the disguise calculator. Only the
/// secret code (typed + `=`) reveals the real app, for this process only.
/// If the session ends while unlocked (logout / token expiry), the disguise
/// snaps back on immediately so a logged-out phone never shows login UI.
class VaultShield extends StatefulWidget {
  const VaultShield({super.key});

  @override
  State<VaultShield> createState() => _VaultShieldState();
}

class _VaultShieldState extends State<VaultShield> {
  AuthStage? _lastStage;

  static const _authedStages = {
    AuthStage.profile,
    AuthStage.pinSetup,
    AuthStage.pinUnlock,
    AuthStage.home,
  };

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultState>();
    final stage = context.watch<AuthState>().stage;
    final wasAuthed = _lastStage != null && _authedStages.contains(_lastStage);
    final loggedOut =
        stage == AuthStage.phone || stage == AuthStage.password;
    _lastStage = stage;
    if (!vault.unlocked) return const CalculatorScreen();
    if (wasAuthed && loggedOut) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<VaultState>().lock();
      });
      return const CalculatorScreen();
    }
    return const AuthGuard();
  }
}

/// Stage-driven router: language? → phone → password → profile → pinSetup → pinUnlock? → home.
/// (OTP stage parked; see seam notes.)
class AuthGuard extends StatelessWidget {
  const AuthGuard({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    // First run: ask the language before anything else. The whole app
    // follows the choice; it stays changeable from More → language.
    if (auth.stage != AuthStage.checking &&
        !context.watch<LanguageState>().picked) {
      return const LanguageScreen();
    }
    switch (auth.stage) {
      case AuthStage.checking:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStage.phone:
        return const PhoneScreen();
      case AuthStage.password:
        return const PasswordScreen();
      // OTP seam (PARKED — unreachable while requestOtp is parked):
      case AuthStage.otp:
        return const PhoneScreen();
      case AuthStage.profile:
        return const ProfileSetupScreen();
      case AuthStage.pinSetup:
        return const PinSetupScreen();
      case AuthStage.pinUnlock:
        return const PinUnlockScreen();
      case AuthStage.home:
        return const HomeScreen();
    }
  }
}
