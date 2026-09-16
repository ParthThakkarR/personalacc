import 'package:shared_preferences/shared_preferences.dart';

/// Token store seam. SharedPreferences keeps the college demo dependency-free;
/// swap [PrefsAuthStorage] for a flutter_secure_storage implementation before
/// any production use (keys stay the same shape: access + refresh).
abstract class AuthStorage {
  Future<StoredSession> read();
  Future<void> write({required String access, required String refresh});
  Future<void> clear();
}

class StoredSession {
  StoredSession(this.access, this.refresh);
  final String? access;
  final String? refresh;
}

class PrefsAuthStorage implements AuthStorage {
  @override
  Future<StoredSession> read() async {
    final prefs = await SharedPreferences.getInstance();
    return StoredSession(
      prefs.getString('khata_access'),
      prefs.getString('khata_refresh'),
    );
  }

  @override
  Future<void> write({required String access, required String refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('khata_access', access);
    await prefs.setString('khata_refresh', refresh);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('khata_access');
    await prefs.remove('khata_refresh');
  }
}
