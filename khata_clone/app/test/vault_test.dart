import 'package:flutter_test/flutter_test.dart';
import 'package:khata_clone_app/core/auth_storage.dart';
import 'package:khata_clone_app/features/vault/calc_engine.dart';
import 'package:khata_clone_app/features/vault/vault_config.dart';
import 'package:khata_clone_app/features/vault/vault_state.dart';

void main() {
  group('CalcEngine', () {
    test('respects operator precedence', () {
      expect(CalcEngine.evaluate('2+3×4'), '14');
      expect(CalcEngine.evaluate('10−2÷2'), '9');
    });

    test('decimals and percent', () {
      expect(CalcEngine.evaluate('0.1+0.2'), '0.3');
      expect(CalcEngine.evaluate('10÷4'), '2.5');
      expect(CalcEngine.evaluate('50%'), '0.5');
    });

    test('unary minus', () {
      expect(CalcEngine.evaluate('−5+2'), '-3');
      expect(CalcEngine.evaluate('3×−2'), '-6');
    });

    test('division by zero reports, not crashes', () {
      expect(() => CalcEngine.evaluate('5÷0'), throwsA(isA<CalcError>()));
    });

    test('malformed input rejected', () {
      expect(() => CalcEngine.evaluate('2+'), throwsA(isA<CalcError>()));
      expect(() => CalcEngine.evaluate('2××3'), throwsA(isA<CalcError>()));
      expect(() => CalcEngine.evaluate(''), throwsA(isA<CalcError>()));
    });
  });

  group('Vault lock', () {
    test('debug build has a usable dev code', () {
      expect(VaultConfig.unlockPossible, isTrue);
      expect(VaultConfig.code, '246800');
    });

    test('wrong code never unlocks', () {
      final vault = VaultState();
      expect(vault.unlocked, isFalse);
      expect(vault.tryUnlock('000000'), isFalse);
      expect(vault.unlocked, isFalse);
      expect(vault.tryUnlock(''), isFalse);
      expect(vault.unlocked, isFalse);
    });

    test('exact code unlocks, lock() re-locks', () {
      final vault = VaultState();
      expect(vault.tryUnlock(VaultConfig.code), isTrue);
      expect(vault.unlocked, isTrue);
      vault.lock();
      expect(vault.unlocked, isFalse);
    });
  });

  group('Ephemeral sessions (close app = logged out)', () {
    test('fresh storage reads empty: a new process never inherits a login', () async {
      final session = MemoryAuthStorage();
      await session.write(access: 'access-token', refresh: 'refresh-token');
      expect((await session.read()).access, 'access-token');
      // A new process gets a new instance with blank RAM — nothing on disk.
      final nextProcess = MemoryAuthStorage();
      final fresh = await nextProcess.read();
      expect(fresh.access, isNull);
      expect(fresh.refresh, isNull);
    });

    test('clear() wipes the in-memory session', () async {
      final session = MemoryAuthStorage();
      await session.write(access: 'a', refresh: 'r');
      await session.clear();
      final wiped = await session.read();
      expect(wiped.access, isNull);
      expect(wiped.refresh, isNull);
    });
  });
}
