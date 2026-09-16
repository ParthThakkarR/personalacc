import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

/// Gate shown on every cold start when the account has a PIN
/// (cf. app_lock_unlock_title + app_locked_timer).
class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key});
  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> {
  final pinCtrl = TextEditingController();

  @override
  void dispose() {
    pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unlock Khata'),
        actions: [
          TextButton(
            onPressed: () => _confirmLogout(context),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Enter your app PIN',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              obscureText: true,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'PIN',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _unlock(context),
            ),
            const SizedBox(height: 12),
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  auth.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: auth.loading ? null : () => _unlock(context),
              child: Text(auth.loading ? 'Unlocking…' : 'Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  void _unlock(BuildContext context) {
    context.read<AuthState>().unlockPin(pinCtrl.text.trim());
  }

  void _confirmLogout(BuildContext context) {
    final auth = context.read<AuthState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need an OTP to log back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
