import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/state.dart';

/// Offline invoice preview (cf. bill_pdf_webview). The HTML string is cached
/// in memory after first fetch, so it renders in airplane mode.
class InvoicePreviewScreen extends StatefulWidget {
  const InvoicePreviewScreen({
    super.key,
    required this.billId,
    required this.title,
    required this.template,
  });
  final int billId;
  final String title;
  final String template;
  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  WebViewController? controller;
  String? error;
  bool seal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final html = await context.read<BillState>().invoiceHtml(
      widget.billId,
      widget.template,
      seal: seal,
    );
    if (!mounted) return;
    if (html == null) {
      setState(
        () => error = context.read<BillState>().error ?? 'Failed to load',
      );
      return;
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadHtmlString(html);
    setState(() => controller = c);
  }

  void _toggleSeal() {
    setState(() {
      seal = !seal;
      controller = null;
      error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Business seal',
            icon: Icon(seal ? Icons.verified : Icons.auto_awesome_outlined),
            onPressed: _toggleSeal,
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!))
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: controller!),
    );
  }
}
