import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/state.dart';
import 'invoice_preview_screen.dart';

/// Bill detail: items + totals + invoice preview/share (cf. fragment_bill_detail).
class BillDetailScreen extends StatefulWidget {
  const BillDetailScreen({super.key, required this.billId});
  final int billId;
  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await context.read<BillState>().detail(widget.billId);
    if (mounted) {
      setState(() {
        data = d;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = data?['bill'];
    final items = (data?['items'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(bill?['invoice_no'] ?? 'Bill')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? const Center(child: Text('Bill not found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...items.map(
                  (it) => ListTile(
                    title: Text(it['name']),
                    subtitle: Text('${it['qty']} x ₹${it['rate']}'),
                    trailing: Text('₹${it['amount']}'),
                  ),
                ),
                const Divider(),
                Text(
                  'Total: ₹${bill['total']}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.preview),
                  label: const Text('Preview invoice'),
                  onPressed: () => _openPreview('standard'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.receipt),
                  label: const Text('Thermal receipt'),
                  onPressed: () => _openPreview('thermal'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share bill'),
                  onPressed: () {
                    Share.share(
                      'Invoice ${bill['invoice_no']} dated ${bill['invoice_date']}: total ₹${bill['total']}.',
                    );
                  },
                ),
              ],
            ),
    );
  }

  void _openPreview(String template) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewScreen(
          billId: widget.billId,
          title: (data?['bill']?['invoice_no'] ?? 'Invoice') as String,
          template: template,
        ),
      ),
    );
  }
}
