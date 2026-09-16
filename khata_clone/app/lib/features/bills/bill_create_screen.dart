import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';
import 'bill_detail_screen.dart';

class _ItemRow {
  final name = TextEditingController();
  final qty = TextEditingController(text: '1');
  final rate = TextEditingController();
  int? itemId;
  void dispose() {
    name.dispose();
    qty.dispose();
    rate.dispose();
  }
}

/// Multi-item bill creator with live GST total (cf. fragment_add_bill).
class BillCreateScreen extends StatefulWidget {
  const BillCreateScreen({super.key});
  @override
  State<BillCreateScreen> createState() => _BillCreateScreenState();
}

class _BillCreateScreenState extends State<BillCreateScreen> {
  final invoiceCtrl = TextEditingController(
    text: 'INV-${DateTime.now().millisecondsSinceEpoch % 100000}',
  );
  final discountCtrl = TextEditingController(text: '0');
  final items = <_ItemRow>[_ItemRow()];
  int slabIndex = 1;

  @override
  void dispose() {
    invoiceCtrl.dispose();
    discountCtrl.dispose();
    for (final it in items) {
      it.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFromInventory(_ItemRow target) async {
    final st = context.read<ItemState>();
    if (st.items.isEmpty) {
      await st.refresh();
    }
    if (!mounted) return;
    final inv = context.read<ItemState>();
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Pick inventory item',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: inv.items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Inventory is empty. Add items first.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: inv.items.length,
                      itemBuilder: (_, i) {
                        final it = inv.items[i];
                        return ListTile(
                          leading: const Icon(
                            Icons.inventory_2,
                            color: Colors.teal,
                          ),
                          title: Text(it['name']),
                          subtitle: Text(
                            'Rate ₹${it['rate']} · stock ${it['stock']}',
                          ),
                          onTap: () {
                            target.itemId = it['id'] as int;
                            target.name.text = it['name'] as String;
                            target.rate.text = '${it['rate']}';
                            slabIndex = (it['gst_slab_index'] as int?) ?? 1;
                            setState(() {});
                            Navigator.pop(sheet);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double get _subtotal {
    double s = 0;
    for (final it in items) {
      s +=
          (double.tryParse(it.qty.text) ?? 0) *
          (int.tryParse(it.rate.text) ?? 0);
    }
    return s;
  }

  double _gstPct(List<dynamic> slabs) {
    if (slabIndex < 0 || slabIndex >= slabs.length) return 0;
    return (slabs[slabIndex]['igst'] as num?)?.toDouble() ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final bills = context.watch<BillState>();
    final slabs = bills.slabs;
    final total =
        _subtotal +
        _subtotal * _gstPct(slabs) / 100 -
        (int.tryParse(discountCtrl.text) ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('New bill')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: invoiceCtrl,
            decoration: const InputDecoration(
              labelText: 'Invoice no',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (slabs.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: slabIndex < slabs.length ? slabIndex : 0,
              decoration: const InputDecoration(
                labelText: 'GST slab',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < slabs.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text('Slab $i — GST ${slabs[i]['igst']}%'),
                  ),
              ],
              onChanged: (v) => setState(() => slabIndex = v ?? 1),
            ),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final it = e.value;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Item ${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (items.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() {
                              items.removeAt(i).dispose();
                            }),
                          ),
                      ],
                    ),
                    TextField(
                      controller: it.name,
                      decoration: const InputDecoration(labelText: 'Item name'),
                      onChanged: (_) => setState(() {}),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _pickFromInventory(it),
                        icon: const Icon(
                          Icons.inventory_2,
                          size: 18,
                          color: Colors.teal,
                        ),
                        label: Text(
                          it.itemId == null
                              ? 'From inventory'
                              : 'Linked to stock item',
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: it.qty,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: const InputDecoration(labelText: 'Qty'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: it.rate,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Rate ₹',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          TextButton.icon(
            onPressed: () => setState(() => items.add(_ItemRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
          TextField(
            controller: discountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Discount ₹',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(
            'Total: ₹${total.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (bills.error != null)
            Text(bills.error!, style: const TextStyle(color: Colors.red)),
          ElevatedButton(
            onPressed: bills.loading
                ? null
                : () async {
                    final rows = <Map<String, dynamic>>[];
                    for (final it in items) {
                      if (it.name.text.trim().isEmpty) continue;
                      rows.add({
                        'name': it.name.text.trim(),
                        'qty': double.tryParse(it.qty.text) ?? 1,
                        'rate': int.tryParse(it.rate.text) ?? 0,
                        if (it.itemId != null) 'item_id': it.itemId,
                      });
                    }
                    if (rows.isEmpty || invoiceCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Add invoice no + at least one item.'),
                        ),
                      );
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    final id = await context.read<BillState>().createBill(
                      invoiceNo: invoiceCtrl.text.trim(),
                      slabIndex: slabIndex,
                      discount: int.tryParse(discountCtrl.text) ?? 0,
                      items: rows,
                    );
                    if (!context.mounted) return;
                    if (id != null) {
                      navigator.pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => BillDetailScreen(billId: id),
                        ),
                      );
                    } else {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            context.read<BillState>().error ?? 'Failed',
                          ),
                        ),
                      );
                    }
                  },
            child: Text(bills.loading ? 'Saving…' : 'Save bill'),
          ),
        ],
      ),
    );
  }
}
