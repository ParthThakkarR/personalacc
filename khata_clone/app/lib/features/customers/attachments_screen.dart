import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/state.dart';

/// Ledger slip attachments for one transaction (cf. ledgerattachment module):
/// photos of hand-written khata / receipts. Stored base64 (max ~400 KB).
class TransactionAttachmentsScreen extends StatefulWidget {
  const TransactionAttachmentsScreen({
    super.key,
    required this.txnId,
    required this.title,
  });
  final int txnId;
  final String title;
  @override
  State<TransactionAttachmentsScreen> createState() =>
      _TransactionAttachmentsScreenState();
}

class _TransactionAttachmentsScreenState
    extends State<TransactionAttachmentsScreen> {
  List<dynamic> atts = [];
  bool loading = true;
  String? error;
  bool uploading = false;

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
      final j = await context.read<ApiClient>().get(
        '/transactions/${widget.txnId}/attachments',
      );
      setState(() => atts = (j as Map)['attachments'] as List);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final api = context.read<ApiClient>();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 900,
    );
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => uploading = true);
    try {
      var data = base64Encode(bytes);
      if (bytes.length > 280000) {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 720);
        final frame = await codec.getNextFrame();
        final out = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        data = base64Encode(out!.buffer.asUint8List());
      }
      await api.post('/transactions/${widget.txnId}/attachments', {
        'mime': 'image/png',
        'caption': x.name,
        'data': data,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} — slips')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: atts.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Text(
                            'No photos attached yet.\nLong-press a ledger entry → "Slips" to add one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: atts.length,
                      itemBuilder: (_, i) {
                        final a = atts[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.image,
                              color: Colors.teal,
                            ),
                            title: Text(
                              (a['caption'] as String?)?.isEmpty ?? true
                                  ? 'Photo ${i + 1}'
                                  : a['caption'] as String,
                            ),
                            subtitle: Text(
                              '${(a['size_bytes'] / 1024).toStringAsFixed(0)} KB',
                            ),
                            trailing: const Icon(Icons.open_in_full),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttachmentViewScreen(
                                    attId: a['id'] as int,
                                    name:
                                        '${(a['caption'] as String?)?.isNotEmpty ?? false ? a['caption'] : 'Photo ${i + 1}'}',
                                  ),
                                ),
                              );
                              if (context.mounted) _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: context.watch<BookState>().can('edit')
          ? FloatingActionButton.extended(
              onPressed: uploading ? null : _pickAndUpload,
              icon: uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library),
              label: Text(uploading ? 'Uploading…' : 'Add photo'),
            )
          : null,
    );
  }
}

/// Full-view of a stored attachment with delete (mimics ledger detail photo).
class AttachmentViewScreen extends StatefulWidget {
  const AttachmentViewScreen({
    super.key,
    required this.attId,
    required this.name,
  });
  final int attId;
  final String name;
  @override
  State<AttachmentViewScreen> createState() => _AttachmentViewScreenState();
}

class _AttachmentViewScreenState extends State<AttachmentViewScreen> {
  Uint8List? bytes;
  String? error;
  String? caption;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await context.read<ApiClient>().get(
        '/transactions/attachments/${widget.attId}/data',
      ) as Map;
      setState(() {
        bytes = base64Decode(j['data'] as String);
        caption = j['caption'] as String?;
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          caption == null || caption!.isEmpty ? widget.name : caption!,
        ),
        actions: [
          if (context.watch<BookState>().can('edit'))
            IconButton(
              tooltip: 'Delete photo',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                try {
                  await context.read<ApiClient>().del(
                    '/transactions/attachments/${widget.attId}',
                  );
                  navigator.pop();
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Delete failed: $e')),
                  );
                }
              },
            ),
        ],
      ),
      body: bytes == null
          ? Center(
              child: error != null
                  ? Text(error!)
                  : const CircularProgressIndicator(),
            )
          : InteractiveViewer(child: Center(child: Image.memory(bytes!))),
    );
  }
}
