import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/lang.dart';
import '../../core/state.dart';

/// Step 2 — OTP verify with resend countdown (cf. login_waiting_for_code).
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final otpCtrl = TextEditingController();

  @override
  void dispose() {
    otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'otp_title')),
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
              'OTP sent to +91 ${auth.phone}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Demo build: the OTP is 123456.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '6-digit OTP',
                border: OutlineInputBorder(),
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
              // OTP seam (PARKED): re-enable with AuthState.verifyOtp when
              // the SMS provider is funded.
              // onPressed: auth.loading
              //     ? null
              //     : () => context.read<AuthState>().verifyOtp(
              //         otpCtrl.text.trim(),
              //       ),
              onPressed: null,
              child: Text(auth.loading ? '…' : tr(context, 'verify_login')),
            ),
            const SizedBox(height: 8),
            TextButton(
              // OTP seam (PARKED): re-enable with AuthState.resendOtp.
              // onPressed: auth.resendAfterS > 0 || auth.loading
              //     ? null
              //     : () => context.read<AuthState>().resendOtp(),
              onPressed: null,
              child: Text(
                auth.resendAfterS > 0
                    ? 'Resend OTP in ${auth.resendAfterS} seconds'
                    : tr(context, 'resend_otp'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
