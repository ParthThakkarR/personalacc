import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/state.dart';

/// Backup export/import (cf. backuprestore). Owner-only endpoints.
/// Export writes a real `.json` file and opens the system share sheet so
/// the user chooses where to keep it (Files, Drive, WhatsApp…).
/// Restore reads a backup file picked from the device — no paste box.
/// Import REPLACES book content — confirmed in the UI before running.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  Map<String, dynamic>? lastExport;
  String? pickedFileName;
  Map<String, dynamic>? pickedPayload;
  bool busy = false;

  Future<void> _export(BuildContext context) async {
    final bin = context.read<RecycleState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final dump = await bin.export();
      if (!context.mounted) return;
      if (dump == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(bin.error ?? 'Export failed')),
        );
        return;
      }
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/khata-backup-$stamp.json');
      await file.writeAsString(jsonEncode(dump));
      final customers = (dump['customers'] as List?)?.length ?? 0;
      final txns = (dump['transactions'] as List?)?.length ?? 0;
      setState(() => lastExport = dump);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        text: 'Khata Clone backup: $customers customers, $txns transactions.',
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Backup file ready — choose where to save it.'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Khata backup', extensions: ['json']),
        ],
      );
      if (!context.mounted) return;
      if (picked == null) return; // user cancelled
      final bytes = await picked.readAsBytes();
      final payload =
          Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      if (payload['version'] != 1 || payload['customers'] is! List) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Not a Khata Clone backup file.')),
        );
        return;
      }
      setState(() {
        pickedFileName = picked.name;
        pickedPayload = payload;
      });
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Invalid backup file.')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bin = context.watch<RecycleState>();
    final customers = (lastExport?['customers'] as List?)?.length;
    final txns = (lastExport?['transactions'] as List?)?.length;
    final pickedCustomers = (pickedPayload?['customers'] as List?)?.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Export',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Saves your full book as a file. You choose where to keep it.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.save_alt),
            label: const Text('Export backup file'),
            onPressed:
                (bin.loading || busy) ? null : () => _export(context),
          ),
          if (lastExport != null) ...[
            const SizedBox(height: 8),
            Text('$customers customers · $txns transactions'),
          ],
          const Divider(height: 32),
          const Text(
            'Restore',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Pick a backup file from your device. WARNING: restore replaces current book content.',
            style: TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(pickedFileName ?? 'Choose backup file'),
            onPressed:
                (bin.loading || busy) ? null : () => _pickFile(context),
          ),
          if (pickedPayload != null) ...[
            const SizedBox(height: 4),
            Text(
              '$pickedFileName: $pickedCustomers customers — ready to restore.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          if (bin.error != null)
            Text(bin.error!, style: const TextStyle(color: Colors.red)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            icon: const Icon(Icons.cloud_upload, color: Colors.white),
            label: const Text(
              'Restore from file',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: (bin.loading || busy || pickedPayload == null)
                ? null
                : () => _confirmImport(context),
          ),
        ],
      ),
    );
  }

  void _confirmImport(BuildContext context) {
    final payload = pickedPayload;
    if (payload == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace book content?'),
        content: Text(
          'Import from $pickedFileName deletes current customers, transactions, bills, links and reminders, then restores from backup. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final bin = context.read<RecycleState>();
              final khata = context.read<KhataState>();
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final ok = await bin.import(payload);
              await khata.refresh();
              if (!context.mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Restore complete.' : (bin.error ?? 'Restore failed'),
                  ),
                ),
              );
            },
            child: const Text('Replace & restore'),
          ),
        ],
      ),
    );
  }
}
