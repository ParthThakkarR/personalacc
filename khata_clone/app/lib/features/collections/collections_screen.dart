import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/state.dart';

/// Collections hub: queue dues reminders + issue mock payment links.
/// Paying a link settles it into the ledger automatically (W7).
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});
  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final selected = <int>{};
  String channel = 'whatsapp';
  final messageCtrl = TextEditingController(
    text: 'Namaste! Your khata balance is due. Please pay soon.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CollectionState>().loadAll();
      context.read<KhataState>().refresh();
    });
  }

  @override
  void dispose() {
    messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = context.watch<CollectionState>();
    final khata = context.watch<KhataState>();
    final book = context.watch<BookState>();
    final dues = ((khata.summary?['perCustomer'] as List?) ?? [])
        .where((c) => ((c['balance'] as num?) ?? 0) > 0)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: RefreshIndicator(
        onRefresh: () => context.read<CollectionState>().loadAll(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'Dues to collect',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (dues.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No pending dues. Great!',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ...dues.map(
              (c) => CheckboxListTile(
                value: selected.contains(c['id']),
                onChanged: book.can('add')
                    ? (v) => setState(() {
                        v == true
                            ? selected.add(c['id'] as int)
                            : selected.remove(c['id']);
                      })
                    : null,
                title: Text(c['name']),
                subtitle: Text('Due ₹${c['balance']}'),
                secondary: IconButton(
                  tooltip: 'Payment link',
                  icon: const Icon(Icons.link),
                  onPressed: book.can('add')
                      ? () => _makeLink(context, c)
                      : null,
                ),
              ),
            ),
            if (book.can('add') && dues.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: channel,
                      decoration: const InputDecoration(
                        labelText: 'Channel',
                        border: OutlineInputBorder(),
                      ),
                      items: const ['sms', 'whatsapp', 'call']
                          .map(
                            (ch) =>
                                DropdownMenuItem(value: ch, child: Text(ch)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => channel = v ?? 'whatsapp'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: messageCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: Text('Remind (${selected.length})'),
                onPressed: selected.isEmpty || col.loading
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final n = await context
                            .read<CollectionState>()
                            .queueReminders(
                              selected.toList(),
                              channel,
                              messageCtrl.text.trim(),
                            );
                        if (!context.mounted) return;
                        if (n != null) {
                          setState(selected.clear);
                          messenger.showSnackBar(
                            SnackBar(content: Text('$n reminder(s) queued.')),
                          );
                        } else {
                          messenger.showSnackBar(
                            SnackBar(content: Text(col.error ?? 'Failed')),
                          );
                        }
                      },
              ),
            ],
            const Divider(height: 32),
            const Text(
              'Payment links',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...col.links.map(
              (l) => ListTile(
                leading: Icon(
                  l['status'] == 'paid' ? Icons.check_circle : Icons.pending,
                  color: l['status'] == 'paid' ? Colors.green : Colors.orange,
                ),
                title: Text('${l['customer_name']} — ₹${l['amount']}'),
                subtitle: Text('${l['ref']} · ${l['status']}'),
                trailing: l['status'] == 'open' && book.can('add')
                    ? TextButton(
                        child: const Text('Simulate pay'),
                        onPressed: () async {
                          final col = context.read<CollectionState>();
                          final kh = context.read<KhataState>();
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await col.payLink(l['ref'] as String);
                          await kh.refresh();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Paid — ledger updated.'
                                    : (col.error ?? 'Failed'),
                              ),
                            ),
                          );
                        },
                      )
                    : null,
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: 'khata-clone://pay/${l['ref']}'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payment link copied.')),
                  );
                },
              ),
            ),
            const Divider(height: 32),
            Text(
              'Reminders sent (${col.reminders.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...col.reminders
                .take(20)
                .map(
                  (r) => ListTile(
                    leading: const Icon(Icons.notifications),
                    title: Text('${r['customer_name']} via ${r['channel']}'),
                    subtitle: Text(r['message'] ?? ''),
                  ),
                ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share app link (demo)'),
              onPressed: () => Share.share(
                'khata-clone://pay — collect dues with Khata Clone!',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _makeLink(BuildContext context, dynamic c) async {
    final amtCtrl = TextEditingController(
      text: '${(c['balance'] as num).toInt()}',
    );
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payment link — ${c['name']}'),
        content: TextField(
          controller: amtCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Amount ₹',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final link = await context.read<CollectionState>().createLink(
      c['id'] as int,
      int.tryParse(amtCtrl.text) ?? 0,
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          link != null
              ? 'Link: ${link['link']}'
              : (context.read<CollectionState>().error ?? 'Failed'),
        ),
      ),
    );
  }
}
