import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';
import 'bill_create_screen.dart';
import 'bill_detail_screen.dart';

/// GST bill list (cf. billbook). Create gated by 'add' permission.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BillState>().loadAll(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = context.watch<BillState>();
    final book = context.watch<BookState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Bills & invoices')),
      body: RefreshIndicator(
        onRefresh: () => context.read<BillState>().loadAll(),
        child: bills.loading && bills.bills.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : bills.error != null && bills.bills.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      bills.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              )
            : bills.bills.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No bills yet. Create your first invoice.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: bills.bills.length,
                itemBuilder: (_, i) {
                  final b = bills.bills[i];
                  return ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text(b['invoice_no']),
                    subtitle: Text('${b['invoice_date']}'),
                    trailing: Text(
                      '₹${b['total']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BillDetailScreen(billId: b['id'] as int),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: book.can('add')
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BillCreateScreen()),
              ),
              label: const Text('New bill'),
              icon: const Icon(Icons.add),
            )
          : null,
    );
  }
}
