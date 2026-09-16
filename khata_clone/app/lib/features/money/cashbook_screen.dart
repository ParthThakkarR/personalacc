import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/lang.dart';
import '../../core/state.dart';

/// Cash register / day book (Phase 9): one day's ledger with a date pager and
/// a running given/received/net summary. Mirrors the "cash register" surface of
/// the researched app (clean-room).
class CashBookScreen extends StatefulWidget {
  const CashBookScreen({super.key});
  @override
  State<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends State<CashBookScreen> {
  DateTime _date = DateTime.now();

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BusinessState>().loadDaybook(date: _dateStr);
    });
  }

  void _shift(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    context.read<BusinessState>().loadDaybook(date: _dateStr);
  }

  void _gotoToday() {
    setState(() => _date = DateTime.now());
    context.read<BusinessState>().loadDaybook(date: _dateStr);
  }

  @override
  Widget build(BuildContext context) {
    final biz = context.watch<BusinessState>();
    final book = context.watch<BookState>();
    final day = biz.daybook;
    final txns = ((day?['transactions'] as List?) ?? []).cast<Map>();
    final isToday = _dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'day_book')),
        actions: [
          if (book.isOwner)
            IconButton(
              tooltip: tr(context, 'sms_on_txn'),
              icon: Icon(
                biz.txnSms ? Icons.sms : Icons.sms_outlined,
                color: biz.txnSms ? const Color(0xFF0B6B3A) : null,
              ),
              onPressed: () => _smsSheet(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        DateFormat('EEEE, d MMM yyyy').format(_date),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (!isToday)
                        TextButton(
                          onPressed: _gotoToday,
                          child: Text(tr(context, 'today')),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          if (day != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _total('Given', day['given'], Colors.red),
                  _total('Received', day['received'], Colors.green),
                  _total(
                    'Net',
                    day['net'],
                    (day['net'] as num?)! >= 0 ? Colors.blue : Colors.orange,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: biz.loading && day == null
                ? const Center(child: CircularProgressIndicator())
                : biz.error != null && day == null
                ? Center(child: Text(biz.error!))
                : txns.isEmpty
                ? Center(
                    child: Text(
                      tr(context, 'no_entries'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => context.read<BusinessState>().loadDaybook(
                      date: _dateStr,
                    ),
                    child: ListView.builder(
                      itemCount: txns.length,
                      itemBuilder: (_, i) {
                        final t = txns[i];
                        final credit = t['kind'] == 'CREDIT';
                        final amt = (t['amount'] as num?) ?? 0;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: credit
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            child: Icon(
                              credit
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: credit ? Colors.red : Colors.green,
                            ),
                          ),
                          title: Text('${t['customer_name'] ?? 'Customer'}'),
                          subtitle: Text(
                            '${t['note'] ?? ''}'.isEmpty
                                ? (credit
                                      ? tr(context, 'you_gave_day')
                                      : tr(context, 'you_received_day'))
                                : '${t['note']}',
                          ),
                          trailing: Text(
                            '₹$amt',
                            style: TextStyle(
                              color: credit ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _total(String label, Object? v, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            '₹${v ?? 0}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );

  void _smsSheet(BuildContext context) {
    final biz = context.read<BusinessState>();
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: SwitchListTile(
          title: Text(tr(context, 'sms_on_txn')),
          subtitle: const Text(
            'Sends a payment receipt SMS to the customer after every entry.',
          ),
          value: biz.txnSms,
          onChanged: (v) {
            biz.setTxnSms(v);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}
