import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/lang.dart';
import '../../core/state.dart';
import 'passbook_screen.dart';
import 'attachments_screen.dart';

/// Customer ledger: balance + day-wise transactions + add CREDIT (udhaar) / DEBIT (payment).
///
/// `initialEntry` ('CREDIT'/'DEBIT') auto-opens the matching entry dialog —
/// used by the home list's one-tap Give/Get shortcuts.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.initialEntry,
  });
  final int customerId;
  final String? initialEntry;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_autoOpened &&
          mounted &&
          (widget.initialEntry == 'CREDIT' ||
              widget.initialEntry == 'DEBIT') &&
          context.read<BookState>().can('add')) {
        _autoOpened = true;
        _txnDialog(
          widget.initialEntry!,
          widget.initialEntry == 'CREDIT' ? 'Give udhaar' : 'Receive payment',
        );
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final j = await api.get('/customers/${widget.customerId}');
      setState(() => data = j as Map<String, dynamic>);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = data?['customer'];
    final bal = data?['balance'] ?? 0;
    final txns = (data?['transactions'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(c?['name'] ?? 'Customer'),
        actions: [
          IconButton(
            tooltip: 'Passbook',
            icon: const Icon(Icons.menu_book),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PassbookScreen(customerId: widget.customerId),
              ),
            ),
          ),
          if (context.watch<BookState>().can('edit'))
            IconButton(
              tooltip: 'Delete customer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Balance: ₹$bal',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: txns.length,
                      itemBuilder: (_, i) {
                        final t = txns[i];
                        final isCredit = t['kind'] == 'CREDIT';
                        final hasAtt =
                            t['has_attachment'] == 1 ||
                            t['has_attachment'] == true;
                        return ListTile(
                          leading: Icon(
                            isCredit
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            color: isCredit ? Colors.red : Colors.green,
                          ),
                          title: Text(
                            '₹${t['amount']} ${isCredit ? "(udhaar)" : "(payment)"}',
                          ),
                          subtitle: Text(
                            '${t['txn_date']}  ${t['note'] ?? ''}',
                          ),
                          trailing: hasAtt
                              ? const Icon(
                                  Icons.image,
                                  color: Colors.teal,
                                  size: 20,
                                )
                              : null,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TransactionAttachmentsScreen(
                                  txnId: t['id'] as int,
                                  title:
                                      '₹${t['amount']} ${isCredit ? "(udhaar)" : "(payment)"}',
                                ),
                              ),
                            );
                            if (context.mounted) _load();
                          },
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: context.watch<BookState>().can('add')
                      ? Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                onPressed: () =>
                                    _txnDialog('CREDIT', 'Give udhaar'),
                                child: Text(
                                  tr(context, 'give_credit'),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                onPressed: () =>
                                    _txnDialog('DEBIT', 'Receive payment'),
                                child: Text(
                                  tr(context, 'receive_debit'),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Read-only access for your role.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                ),
              ],
            ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to recycle bin?'),
        content: const Text(
          'The customer and ledger stay recoverable for now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              try {
                await context.read<ApiClient>().del(
                  '/customers/${widget.customerId}',
                );
                navigator.pop(true);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Delete failed: $e')),
                );
              }
            },
            child: const Text(
              'Move to bin',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _txnDialog(String kind, String title) {
    final amt = TextEditingController();
    final note = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amt,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Amount ₹'),
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            TextField(
              controller: note,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Note'),
              onSubmitted: (_) => _saveTxn(kind, amt, note),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _saveTxn(kind, amt, note),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTxn(
    String kind,
    TextEditingController amt,
    TextEditingController note,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = int.tryParse(amt.text.trim()) ?? 0;
    if (amount <= 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr(context, 'amount_invalid'))),
      );
      return;
    }
    final khata = context.read<KhataState>();
    final navigator = Navigator.of(context);
    final ok = await khata.addTxn(
      widget.customerId,
      kind,
      amount,
      note.text.trim(),
    );
    if (!mounted) return;
    navigator.pop();
    if (ok) {
      _load();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(khata.error ?? 'Failed to save')),
      );
    }
  }
}
