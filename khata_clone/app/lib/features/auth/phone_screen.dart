import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/lang.dart';
import '../../core/state.dart';

/// Step 1 — phone number (cf. layout_login_number_input + trust badge).
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final phoneCtrl = TextEditingController();

  @override
  void dispose() {
    phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Khata Clone')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(context, 'login_title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'login_sub'),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: tr(context, 'phone_label'),
                prefixText: '+91 ',
                border: const OutlineInputBorder(),
              ),
            ),
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
                  : () => context.read<AuthState>().goToPassword(
                      phoneCtrl.text.trim(),
                    ),
              child: Text(auth.loading ? '…' : tr(context, 'continue')),
            ),
          ],
        ),
      ),
    );
  }
}
