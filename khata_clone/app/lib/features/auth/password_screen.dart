import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lang.dart';
import '../../core/state.dart';

/// Step 2 (password mode) — login or create account.
/// Same number + password on any device syncs the same books
/// (account-based sync; cf. POST /auth/login|register).
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final passCtrl = TextEditingController();
  bool showPassword = false;
  bool isRegister = false;

  @override
  void dispose() {
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(isRegister
            ? tr(context, 'register_btn')
            : tr(context, 'login_btn')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.read<AuthState>().backToPhone(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '+91 ${auth.phone}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              isRegister
                  ? tr(context, 'new_here')
                  : tr(context, 'have_account'),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: !showPassword,
              maxLength: 72,
              decoration: InputDecoration(
                labelText: tr(context, 'password_label'),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(showPassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => showPassword = !showPassword),
                ),
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
                  : () {
                      final pw = passCtrl.text;
                      final a = context.read<AuthState>();
                      if (isRegister) {
                        a.registerWithPassword(pw);
                      } else {
                        a.loginWithPassword(pw);
                      }
                    },
              child: Text(auth.loading
                  ? '…'
                  : (isRegister
                      ? tr(context, 'register_btn')
                      : tr(context, 'login_btn'))),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: auth.loading
                  ? null
                  : () => setState(() => isRegister = !isRegister),
              child: Text(isRegister
                  ? tr(context, 'have_account')
                  : tr(context, 'new_here')),
            ),
          ],
        ),
      ),
    );
  }
}
