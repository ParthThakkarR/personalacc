import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/lang.dart';
import '../../core/state.dart';

/// Business card with scannable QR (Phase 8). The QR encodes a vCard-style
/// payload served by GET /business/card — mirrors the shareable business card
/// surface of the researched app (clean-room).
class BusinessCardScreen extends StatefulWidget {
  const BusinessCardScreen({super.key});
  @override
  State<BusinessCardScreen> createState() => _BusinessCardScreenState();
}

class _BusinessCardScreenState extends State<BusinessCardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BusinessState>().loadEngagement(),
    );
  }

  Future<void> _shareCard() async {
    final card = context.read<BusinessState>().card;
    await Share.share(
      '${card?['name'] ?? ''}\n${card?['business_name'] ?? ''}\n${card?['phone'] ?? ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final biz = context.watch<BusinessState>();
    final card = biz.card;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'business_card'))),
      body: biz.loading && card == null
          ? const Center(child: CircularProgressIndicator())
          : biz.error != null && card == null
          ? Center(child: Text(biz.error!))
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0B6B3A), Color(0xFF148A4C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${card?['business_name'] ?? ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${card?['business_category'] ?? ''}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const Divider(color: Colors.white24),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${card?['name'] ?? ''}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${card?['phone'] ?? ''}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          QrImageView(
                            data: '${card?['qr_payload'] ?? ''}',
                            version: QrVersions.auto,
                            size: 180,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(context, 'scan_this_card'),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: '${card?['qr_payload'] ?? ''}',
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr(context, 'saved'))),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: Text(tr(context, 'copy_code')),
                        ),
                        FilledButton.icon(
                          onPressed: _shareCard,
                          icon: const Icon(Icons.share),
                          label: Text(tr(context, 'share_card')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
