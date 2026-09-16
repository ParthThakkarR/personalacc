import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

/// Recycle bin: restore or purge soft-deleted customers/transactions.
class RecycleScreen extends StatefulWidget {
  const RecycleScreen({super.key});
  @override
  State<RecycleScreen> createState() => _RecycleScreenState();
}

class _RecycleScreenState extends State<RecycleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<RecycleState>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bin = context.watch<RecycleState>();
    final book = context.watch<BookState>();
    final canEdit = book.can('edit');
    return Scaffold(
      appBar: AppBar(title: const Text('Recycle bin')),
      body: RefreshIndicator(
        onRefresh: () => context.read<RecycleState>().load(),
        child: bin.loading && bin.customers.isEmpty && bin.transactions.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Text(
                    'Deleted customers',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...bin.customers.map(
                    (c) => ListTile(
                      leading: const Icon(Icons.person_off),
                      title: Text(c['name']),
                      subtitle: Text(c['phone'] ?? ''),
                      trailing: canEdit
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Restore',
                                  icon: const Icon(
                                    Icons.restore,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => context
                                      .read<RecycleState>()
                                      .restoreCustomer(c['id'] as int),
                                ),
                                IconButton(
                                  tooltip: 'Delete forever',
                                  icon: const Icon(
                                    Icons.delete_forever,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _confirmPurge(
                                    context,
                                    'customer',
                                    c['id'] as int,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                  if (bin.customers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('None', style: TextStyle(color: Colors.grey)),
                    ),
                  const Divider(),
                  const Text(
                    'Deleted transactions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...bin.transactions.map(
                    (t) => ListTile(
                      leading: const Icon(Icons.money_off),
                      title: Text(
                        '₹${t['amount']} ${t['kind'] == 'CREDIT' ? '(udhaar)' : '(payment)'}',
                      ),
                      subtitle: Text(
                        '${t['customer_name']} · ${t['txn_date']}',
                      ),
                      trailing: canEdit
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Restore',
                                  icon: const Icon(
                                    Icons.restore,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => context
                                      .read<RecycleState>()
                                      .restoreTxn(t['id'] as int),
                                ),
                                IconButton(
                                  tooltip: 'Delete forever',
                                  icon: const Icon(
                                    Icons.delete_forever,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _confirmPurge(
                                    context,
                                    'txn',
                                    t['id'] as int,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                  if (bin.transactions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('None', style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
      ),
    );
  }

  void _confirmPurge(BuildContext context, String kind, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text(
          'This cannot be undone. Restore instead if unsure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final bin = context.read<RecycleState>();
              Navigator.pop(ctx);
              final ok = kind == 'customer'
                  ? await bin.purgeCustomer(id)
                  : await bin.purgeTxn(id);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(bin.error ?? 'Failed')));
              }
            },
            child: const Text(
              'Delete forever',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
