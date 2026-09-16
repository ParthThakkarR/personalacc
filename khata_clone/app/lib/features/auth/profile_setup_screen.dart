import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

/// Step 3 — business onboarding (cf. fragment_business_and_owner_name,
/// fragment_business_category, fragment_business_name). Categories come from
/// the bundled business_categories.json observed in the APK assets.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final nameCtrl = TextEditingController();
  final businessCtrl = TextEditingController();
  TextEditingController? _categoryFieldCtrl;
  List<String> categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/business_categories.json',
      );
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      final names =
          list
              .map((e) => (e['bc_n'] as String).trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (mounted) setState(() => categories = names);
    } catch (_) {}
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    businessCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Your business')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tell us about your shop',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: businessCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Business name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (v) {
                if (v.text.isEmpty) return const Iterable<String>.empty();
                final q = v.text.toLowerCase();
                return categories.where((c) => c.toLowerCase().contains(q));
              },
              fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                _categoryFieldCtrl = ctrl;
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(
                    labelText: 'Business category (optional)',
                    border: OutlineInputBorder(),
                  ),
                );
              },
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
                      final cat = _categoryFieldCtrl?.text.trim() ?? '';
                      context.read<AuthState>().saveProfile(
                        name: nameCtrl.text,
                        business: businessCtrl.text,
                        category: cat.isEmpty ? null : cat,
                      );
                    },
              child: Text(auth.loading ? 'Saving…' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
