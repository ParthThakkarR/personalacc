import 'package:flutter/foundation.dart';

import 'vault_config.dart';

/// Process-lifetime vault lock.
///
/// Unlocked only by entering the secret calculator code. The unlocked flag
/// is NEVER persisted — every cold start begins locked, and [lock] is called
/// automatically when the user logs out or the session expires (see
/// VaultShield in main.dart).
class VaultState extends ChangeNotifier {
  bool _unlocked = false;

  bool get unlocked => _unlocked && VaultConfig.unlockPossible;

  /// Returns true when [digits] (the raw calculator entry) is the code.
  /// Anything else returns false and leaves the calculator behaving
  /// normally — a wrong guess just computes a number, revealing nothing.
  bool tryUnlock(String digits) {
    if (!VaultConfig.unlockPossible) return false;
    if (digits.isNotEmpty && digits == VaultConfig.code) {
      _unlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void lock() {
    if (_unlocked) {
      _unlocked = false;
      notifyListeners();
    }
  }
}
