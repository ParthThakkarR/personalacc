import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lang.dart';

/// First-run step: ask the user's language before anything else.
/// The whole app (every `tr()` string) follows this choice; it can be
/// changed later from More → language.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.translate, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Choose your language\nअपनी भाषा चुनें',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _option(context, 'English', 'Continue in English', 'en'),
              const SizedBox(height: 12),
              _option(context, 'हिन्दी', 'हिन्दी में आगे बढ़ें', 'hi'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    String title,
    String subtitle,
    String code,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: () => context.read<LanguageState>().setCode(code),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
