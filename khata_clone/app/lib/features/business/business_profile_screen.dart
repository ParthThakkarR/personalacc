import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/lang.dart';
import '../../core/state.dart';

/// Business profile editing (Phase 10): name, business name, category, phone.
/// Writes via PATCH /auth/profile (same endpoint as onboarding) and refreshes
/// in-memory user state. Mirrors the "business profile" surface (clean-room).
class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});
  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final nameCtrl = TextEditingController();
  final businessCtrl = TextEditingController();
  final categoryCtrl = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  void _prefill() {
    final u = context.read<AuthState>().user;
    nameCtrl.text = '${u?['name'] ?? ''}';
    businessCtrl.text = '${u?['business_name'] ?? ''}';
    categoryCtrl.text = '${u?['business_category'] ?? ''}';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    businessCtrl.dispose();
    categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final api = context.read<ApiClient>();
    final auth = context.read<AuthState>();
    if (nameCtrl.text.trim().isEmpty || businessCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and business name are required.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await api.patch('/auth/profile', {
        'name': nameCtrl.text.trim(),
        'business_name': businessCtrl.text.trim(),
        if (categoryCtrl.text.trim().isNotEmpty)
          'business_category': categoryCtrl.text.trim(),
      });
      await auth.refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(context, 'saved'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AuthState.friendly(e))));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthState>().user;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'business_profile'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone),
              title: Text('${u?['phone'] ?? ''}'),
              subtitle: const Text('Mobile number (login ID)'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Your name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: businessCtrl,
            decoration: const InputDecoration(
              labelText: 'Business name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: categoryCtrl,
            decoration: const InputDecoration(
              labelText: 'Business category',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(tr(context, 'save')),
          ),
        ],
      ),
    );
  }
}
