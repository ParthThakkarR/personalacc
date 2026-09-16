import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

/// Step 4 — Khatabook-PIN setup (cf. app_lock_enroll_title). Required before
/// first Home so every account has AppLock-grade protection from day one.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});
  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final pinCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  @override
  void dispose() {
    pinCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Set app PIN')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Protect your khata with a PIN',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'You will enter it every time the app starts.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'New PIN (4–8 digits)',
                border: OutlineInputBorder(),
              ),
            ),
            TextField(
              controller: confirmCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  auth.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: auth.loading
                  ? null
                  : () {
                      final pin = pinCtrl.text.trim();
                      if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('PIN must be 4–8 digits.'),
                          ),
                        );
                        return;
                      }
                      if (pin != confirmCtrl.text.trim()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PINs do not match.')),
                        );
                        return;
                      }
                      context.read<AuthState>().setPin(pin);
                    },
              child: Text(auth.loading ? 'Saving…' : 'Set PIN & Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
