import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';
import 'activity_screen.dart';

/// Owner's staff list: invite by phone + role, change role, revoke
/// (cf. stafftab + accesscontrol onboarding).
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BookState>().loadStaff(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = context.watch<BookState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & access'),
        actions: [
          IconButton(
            tooltip: 'Activity log',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActivityScreen()),
            ),
          ),
        ],
      ),
      body: book.loading && book.staff.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : book.error != null && book.staff.isEmpty
          ? Center(child: Text(book.error!))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Roles: viewer (see only) · entry (add) · manager (add + edit + reports)',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ...book.staff.map((s) {
                  final active = s['status'] == 'active';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: active
                          ? Colors.green.shade100
                          : Colors.grey.shade300,
                      child: Text((s['phone'] as String).substring(6)),
                    ),
                    title: Text('+91 ${s['phone']}'),
                    subtitle: Text('${s['role']} · ${s['status']}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _onMenu(context, v, s),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'manager',
                          child: Text('Make manager'),
                        ),
                        PopupMenuItem(
                          value: 'entry',
                          child: Text('Make entry staff'),
                        ),
                        PopupMenuItem(
                          value: 'viewer',
                          child: Text('Make viewer'),
                        ),
                        PopupMenuItem(
                          value: 'revoke',
                          child: Text(
                            'Revoke access',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (book.staff.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No staff yet. Invite by phone number.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _inviteDialog(context),
        label: const Text('Invite'),
        icon: const Icon(Icons.person_add),
      ),
    );
  }

  void _onMenu(BuildContext context, String v, dynamic s) async {
    final book = context.read<BookState>();
    final messenger = ScaffoldMessenger.of(context);
    final phone = s['phone'] as String;
    final ok = v == 'revoke'
        ? await book.revoke(phone)
        : await book.setRole(phone, v);
    if (!ok && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(book.error ?? 'Failed')));
    }
  }

  void _inviteDialog(BuildContext context) {
    final phone = TextEditingController();
    String role = 'entry';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Invite staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Staff mobile number',
                  prefixText: '+91 ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: BookState.allRoles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setD(() => role = v ?? 'entry'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final book = context.read<BookState>();
                final messenger = ScaffoldMessenger.of(context);
                final ok = await book.invite(phone.text.trim(), role);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Invite sent — staff logs in with OTP'
                            : (book.error ?? 'Invite failed'),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Send invite'),
            ),
          ],
        ),
      ),
    );
  }
}
