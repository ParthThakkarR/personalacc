import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

/// Owner dashboard / insights (cf. userdashboard): headline dues, 6-month
/// net trend, top creditors, and this-month expense. Totals-gated.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardState>().refresh();
    });
  }

  double _maxVal(List<dynamic> trend) {
    double m = 0;
    for (final t in trend) {
      final g = ((t['given'] as num?) ?? 0).toDouble();
      final r = ((t['received'] as num?) ?? 0).toDouble();
      if (g > m) m = g;
      if (r > m) m = r;
    }
    return m == 0 ? 1 : m;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DashboardState>();
    final data = d.data;
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: d.loading && data == null
          ? const Center(child: CircularProgressIndicator())
          : d.error != null && data == null
          ? Center(child: Text(d.error!))
          : RefreshIndicator(
              onRefresh: d.refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (d.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        d.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  Card(
                    color: Colors.red.shade50,
                    child: ListTile(
                      leading: const Icon(
                        Icons.arrow_upward,
                        color: Colors.red,
                      ),
                      title: const Text('You will receive'),
                      trailing: Text(
                        '₹${data?['receivable'] ?? 0}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  Card(
                    color: Colors.blue.shade50,
                    child: ListTile(
                      leading: const Icon(
                        Icons.arrow_downward,
                        color: Colors.blue,
                      ),
                      title: const Text('You will pay'),
                      trailing: Text(
                        '₹${data?['payable'] ?? 0}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '6-month net (₹)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 120,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final t in (data?['trend'] as List? ?? []))
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        _bar(
                                          '${t['month']}'.substring(5),
                                          ((t['given'] as num?) ?? 0)
                                              .toDouble(),
                                          _maxVal(
                                            data?['trend'] as List? ?? [],
                                          ),
                                          Colors.red,
                                        ),
                                        const SizedBox(height: 4),
                                        _bar(
                                          null,
                                          ((t['received'] as num?) ?? 0)
                                              .toDouble(),
                                          _maxVal(
                                            data?['trend'] as List? ?? [],
                                          ),
                                          Colors.green,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Red = udhaar given · green = received',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.receipt_long,
                        color: Colors.orange,
                      ),
                      title: const Text('This month expense'),
                      trailing: Text(
                        '₹${data?['this_month_expense'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.teal,
                      ),
                      title: const Text('This month bookkeeping'),
                      trailing: Text(
                        '₹${data?['this_month_net'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.people, color: Colors.indigo),
                      title: const Text('Customers'),
                      trailing: Text(
                        '${data?['customer_count'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Top dues',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final c in (data?['top_dues'] as List? ?? []))
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        child: Text(
                          (c['name'] as String).isNotEmpty
                              ? (c['name'] as String)[0]
                              : '?',
                        ),
                      ),
                      title: Text(c['name']),
                      subtitle: Text(c['phone'] ?? ''),
                      trailing: Text(
                        '₹${c['balance']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _bar(String? label, double v, double max, Color color) {
    final h = 100 * (v / max);
    return Column(
      children: [
        if (label != null) Text(label, style: const TextStyle(fontSize: 10)),
        Container(
          width: 14,
          height: h.clamp(2, 100),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    );
  }
}
