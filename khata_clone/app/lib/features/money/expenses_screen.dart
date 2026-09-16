import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

const _categories = [
  'Rent',
  'Salary',
  'Electricity',
  'Water',
  'Transport',
  'Raw material',
  'Other',
];

/// Expense tracker (cf. finance/expenses): add/delete expenses, month filter.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String? month; // null = all months
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExpenseState>().refresh();
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _picked ?? now,
      firstDate: DateTime(now.year - 2, 1),
      lastDate: now,
    );
    if (d == null) return;
    if (!mounted) return;
    setState(() {
      _picked = d;
      month =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
    });
    context.read<ExpenseState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ExpenseState>();
    final rows = month == null
        ? st.expenses
        : st.expenses
              .where((e) => (e['expense_date'] as String).startsWith(month!))
              .toList();
    final total = rows.fold<int>(
      0,
      (s, e) => s + ((e['amount'] as num?) ?? 0).toInt(),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          TextButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.date_range, color: Colors.black87),
            label: Text(month ?? 'All months'),
          ),
          if (month != null)
            IconButton(
              tooltip: 'Clear filter',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => month = null),
            ),
        ],
      ),
      body: st.loading && st.expenses.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : st.error != null && st.expenses.isEmpty
          ? Center(child: Text(st.error!))
          : RefreshIndicator(
              onRefresh: st.refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.receipt_long,
                        color: Colors.orange,
                      ),
                      title: const Text('Filtered total'),
                      trailing: Text(
                        '₹$total',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No expenses.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ...rows.map(
                    (e) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade50,
                        child: Text(
                          (e['category'] as String?)?.substring(
                                0,
                                ((e['category'] as String?)?.length ?? 1) > 1
                                    ? 1
                                    : 1,
                              ) ??
                              'E',
                        ),
                      ),
                      title: Text(e['note'] ?? e['category'] ?? 'Expense'),
                      subtitle: Text(
                        '${e['expense_date']} · ${e['category'] ?? ''}',
                      ),
                      trailing: Text(
                        '₹${e['amount']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onLongPress: context.watch<BookState>().can('edit')
                          ? () => _confirmDelete(context, e['id'] as int)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: context.watch<BookState>().can('add')
          ? FloatingActionButton.extended(
              onPressed: () => _addDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            )
          : null,
    );
  }

  void _addDialog(BuildContext context) {
    final amt = TextEditingController();
    final note = TextEditingController();
    String cat = _categories.first;
    showDialog(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, setDlg) => AlertDialog(
          title: const Text('New expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amt,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Amount ₹'),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: cat,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setDlg(() => cat = v ?? _categories.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final ok = await context.read<ExpenseState>().add(
                  int.tryParse(amt.text.trim()) ?? 0,
                  note.text.trim(),
                  cat,
                );
                if (dlg.mounted) Navigator.pop(dlg);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to add expense')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text('Moves to recycle bin — recoverable.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final ok = await context.read<ExpenseState>().remove(id);
              if (dlg.mounted) Navigator.pop(dlg);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete expense')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
