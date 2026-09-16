import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

/// Inventory item master (cf. inventory module): items with rate + stock,
/// total stock value, and add/edit/delete. Bills deduct stock on issue.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ItemState>().refresh();
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ItemState>();
    final q = searchCtrl.text.toLowerCase();
    final rows = st.items
        .where(
          (it) => q.isEmpty || (it['name'] as String).toLowerCase().contains(q),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: st.loading && st.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : st.error != null && st.items.isEmpty
          ? Center(child: Text(st.error!))
          : RefreshIndicator(
              onRefresh: st.refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.inventory_2,
                        color: Colors.teal,
                      ),
                      title: const Text('Total stock value'),
                      trailing: Text(
                        '₹${st.totalStockValue}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search items',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No items in inventory.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ...rows.map(
                    (it) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade50,
                        child: Text(
                          (it['name'] as String).isNotEmpty
                              ? (it['name'] as String)[0]
                              : '?',
                        ),
                      ),
                      title: Text(it['name']),
                      subtitle: Text(
                        'Rate ₹${it['rate']} · stock ${it['stock']} ${it['unit'] ?? ''}',
                      ),
                      trailing: Text(
                        '₹${(it['rate'] as num) * (it['stock'] as num)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onLongPress: context.watch<BookState>().can('edit')
                          ? () => _itemDialog(context, it)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: context.watch<BookState>().can('add')
          ? FloatingActionButton.extended(
              onPressed: () => _itemDialog(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            )
          : null,
    );
  }

  void _itemDialog(BuildContext context, dynamic existing) {
    final name = TextEditingController(text: existing?['name'] ?? '');
    final unit = TextEditingController(text: existing?['unit'] ?? '');
    final rate = TextEditingController(text: '${existing?['rate'] ?? ''}');
    final stock = TextEditingController(text: '${existing?['stock'] ?? ''}');
    int slab = (existing?['gst_slab_index'] as int?) ?? 1;
    showDialog(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, setDlg) => AlertDialog(
          title: Text(existing == null ? 'New item' : 'Edit item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Item name'),
              ),
              TextField(
                controller: unit,
                decoration: const InputDecoration(labelText: 'Unit (kg, pc…)'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rate,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Rate ₹'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: stock,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Stock'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: slab,
                decoration: const InputDecoration(labelText: 'GST slab'),
                items: [
                  for (
                    var i = 0;
                    i < context.read<BillState>().slabs.length;
                    i++
                  )
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        'Slab $i — GST ${context.watch<BillState>().slabs[i]['igst']}%',
                      ),
                    ),
                ],
                onChanged: (v) => setDlg(() => slab = v ?? 1),
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
                final st = context.read<ItemState>();
                final ok = existing == null
                    ? await st.add({
                        'name': name.text.trim(),
                        'unit': unit.text.trim(),
                        'rate': int.tryParse(rate.text.trim()) ?? 0,
                        'stock': int.tryParse(stock.text.trim()) ?? 0,
                        'gst_slab_index': slab,
                      })
                    : await st.update(existing['id'] as int, {
                        'name': name.text.trim(),
                        'unit': unit.text.trim(),
                        'rate': int.tryParse(rate.text.trim()) ?? 0,
                        'stock': int.tryParse(stock.text.trim()) ?? 0,
                        'gst_slab_index': slab,
                      });
                if (dlg.mounted) Navigator.pop(dlg);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to save item')),
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
}
