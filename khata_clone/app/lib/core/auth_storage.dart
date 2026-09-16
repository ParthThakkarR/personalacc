/// Session store seam.
///
/// MAX-SECURITY MODE: sessions live in RAM only ([MemoryAuthStorage]).
/// Nothing secret is ever written to the phone's disk, so killing the app
/// always means logged out — the next cold start requires the vault code +
/// phone/password (+ PIN) again. There is deliberately no "remember me".
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

/// RAM-only store. A fresh instance reads empty, which is exactly what a new
/// app process gets — this is what makes "close app = logged out" certain
/// rather than best-effort (no lifecycle callbacks to miss, no files to wipe,
// no forensic residue of tokens on disk).
class MemoryAuthStorage implements AuthStorage {
  String? _access;
  String? _refresh;

  @override
  Future<StoredSession> read() async => StoredSession(_access, _refresh);

  @override
  Future<void> write({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
