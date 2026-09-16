import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api_client.dart';

/// Customer passbook: bank-style statement with running balance + printable
/// HTML share/preview (cf. passbook/statement module).
class PassbookScreen extends StatefulWidget {
  const PassbookScreen({super.key, required this.customerId});
  final int customerId;
  @override
  State<PassbookScreen> createState() => _PassbookScreenState();
}

class _PassbookScreenState extends State<PassbookScreen> {
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final j = await api.get('/customers/${widget.customerId}/passbook');
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
    final summary = data?['summary'] ?? {};
    final entries = (data?['entries'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passbook'),
        actions: [
          IconButton(
            tooltip: 'Printable passbook',
            icon: const Icon(Icons.print),
            onPressed: () => _openHtml(context),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.teal.shade50,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c?['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(c?['phone'] ?? ''),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Opening  ₹${summary['opening'] ?? 0}'),
                            Text(
                              'Udhaar ₹${summary['total_credit'] ?? 0}',
                              style: const TextStyle(color: Colors.red),
                            ),
                            Text(
                              'Paid ₹${summary['total_debit'] ?? 0}',
                              style: const TextStyle(color: Colors.green),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Closing balance: ₹${summary['closing'] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Table(
                    border: const TableBorder(
                      bottom: BorderSide(color: Colors.grey),
                      horizontalInside: BorderSide(color: Colors.black12),
                    ),
                    children: [
                      const TableRow(
                        children: [
                          _Cell('Date', bold: true),
                          _Cell('Particulars', bold: true),
                          _Cell('Udhaar', bold: true, right: true),
                          _Cell('Paid', bold: true, right: true),
                          _Cell('Balance', bold: true, right: true),
                        ],
                      ),
                      ...entries.map((e) {
                        final isC = (e['kind'] as String) == 'CREDIT';
                        return TableRow(
                          children: [
                            _Cell('${e['txn_date']}'),
                            _Cell(
                              '${e['note'] ?? (isC ? 'Udhaar' : 'Payment')}',
                            ),
                            _Cell(
                              isC ? '₹${e['amount']}' : '',
                              right: true,
                              color: isC ? Colors.red : null,
                            ),
                            _Cell(
                              !isC ? '₹${e['amount']}' : '',
                              right: true,
                              color: !isC ? Colors.green : null,
                            ),
                            _Cell('₹${e['running_balance']}', right: true),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  void _openHtml(BuildContext context) async {
    final api = context.read<ApiClient>();
    final navigator = Navigator.of(context);
    final html = await api.getRaw(
      '/customers/${widget.customerId}/passbook.html',
    );
    if (!mounted) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => _PassbookHtmlScreen(
          html: html,
          name: '${(data?['customer'] as Map?)?['name'] ?? 'Passbook'}',
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false, this.right = false, this.color});
  final String text;
  final bool bold;
  final bool right;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : null,
          color: color,
        ),
      ),
    );
  }
}

class _PassbookHtmlScreen extends StatefulWidget {
  const _PassbookHtmlScreen({required this.html, required this.name});
  final String html;
  final String name;
  @override
  State<_PassbookHtmlScreen> createState() => _PassbookHtmlScreenState();
}

class _PassbookHtmlScreenState extends State<_PassbookHtmlScreen> {
  WebViewController? controller;
  @override
  void initState() {
    super.initState();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadHtmlString(widget.html);
    controller = c;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: WebViewWidget(controller: controller!),
    );
  }
}
