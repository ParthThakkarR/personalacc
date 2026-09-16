import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/lang.dart';
import '../../core/state.dart';

/// Refer & earn (Phase 8): invite code + share, reward stats, claim a friend's
/// code. Mirrors the engagement surface of the researched app (clean-room).
class ReferScreen extends StatefulWidget {
  const ReferScreen({super.key});
  @override
  State<ReferScreen> createState() => _ReferScreenState();
}

class _ReferScreenState extends State<ReferScreen> {
  final codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BusinessState>().loadEngagement(),
    );
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, 'saved'))));
  }

  Future<void> _share(String code, String business) async {
    await Share.share(
      '$business: use my referral code $code on Khata Clone and both of us get a ₹100 bonus!',
    );
  }

  Future<void> _claim() async {
    final ok = await context.read<BusinessState>().claim(codeCtrl.text);
    if (!mounted) return;
    final biz = context.read<BusinessState>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${tr(context, 'claimed_bonus')}${biz.lastClaimBonus}'
              : (biz.error ?? 'Failed'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final biz = context.watch<BusinessState>();
    final ref = biz.referral;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'refer_earn'))),
      body: biz.loading && ref == null
          ? const Center(child: CircularProgressIndicator())
          : biz.error != null && ref == null
          ? Center(child: Text(biz.error!))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: const Color(0xFF0B6B3A),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          tr(context, 'refer_earn'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Share invite code · both earn ₹${ref?['bonus_per_friend'] ?? 100}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          '${ref?['code'] ?? '----'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            letterSpacing: 6,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _copy('${ref?['code'] ?? ''}'),
                              icon: const Icon(Icons.copy, size: 18),
                              label: Text(tr(context, 'copy_code')),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _share(
                                '${ref?['code'] ?? ''}',
                                '${ref?['code'] ?? ''}',
                              ),
                              icon: const Icon(Icons.share, size: 18),
                              label: Text(tr(context, 'share_code')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _stat(
                        tr(context, 'bonus_per_friend'),
                        '₹${ref?['bonus_per_friend'] ?? 100}',
                      ),
                    ),
                    Expanded(
                      child: _stat(
                        tr(context, 'friends_joined'),
                        '${ref?['friends'] ?? 0}',
                      ),
                    ),
                    Expanded(
                      child: _stat(
                        tr(context, 'total_earned'),
                        '₹${ref?['earned'] ?? 0}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: tr(context, 'claim_code'),
                    prefixIcon: const Icon(Icons.card_giftcard),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _claim,
                  icon: const Icon(Icons.redeem),
                  label: Text(tr(context, 'claim')),
                ),
              ],
            ),
    );
  }

  Widget _stat(String label, String value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
