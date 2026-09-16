/// Stealth-vault configuration.
///
/// The app launches as an ordinary calculator. Typing the secret [code]
/// (digits only) and pressing `=` unlocks the real ledger app for this
/// process lifetime only — every cold start begins locked.
///
/// The code is baked in at BUILD time, e.g.:
/// ```sh
/// flutter build apk --release \
///   --dart-define=VAULT_CODE=847120 \
///   --dart-define=API_BASE_URL=https://your-backend.onrender.com
/// ```
///
/// Rules: 4–12 digits, nothing else.
///  - Release build with missing/invalid code → vault can NEVER unlock
///    (fail closed). You must rebuild with a valid `--dart-define`.
///  - Debug builds fall back to `246800` so developers and `flutter test`
///    work without flags. NEVER ship a release build without VAULT_CODE.
///
/// Security note (stated honestly): the calculator is a DISGUISE against
/// casual snooping — someone opening the phone sees a working calculator.
/// Real protection is server-side: ALLOWED_PHONES allow-list + passwords +
/// PIN + short-lived JWTs. Never rely on the disguise alone.
class VaultConfig {
  static const _envCode = String.fromEnvironment('VAULT_CODE', defaultValue: '');
  static final _codePattern = RegExp(r'^[0-9]{4,12}$');

  static bool get isRelease => bool.fromEnvironment('dart.vm.product');

  static String get code {
    if (_envCode.isNotEmpty && _codePattern.hasMatch(_envCode)) {
      return _envCode;
    }
    // Fail closed in release: no/invalid code → the vault stays shut.
    if (isRelease) return '';
    return '246800';
  }

  static bool get unlockPossible => code.isNotEmpty;
}
