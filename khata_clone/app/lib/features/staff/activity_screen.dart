import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/state.dart';

/// Owner alert feed: every staff write, newest first
/// (cf. "alerts every time a staff makes a new entry").
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BookState>().loadActivity(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = context.watch<BookState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Staff activity')),
      body: RefreshIndicator(
        onRefresh: () => context.read<BookState>().loadActivity(),
        child: book.loading && book.activity.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : book.activity.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No staff activity yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: book.activity.length,
                itemBuilder: (_, i) {
                  final a = book.activity[i];
                  final dt = DateTime.fromMillisecondsSinceEpoch(
                    a['created_at'] as int,
                  );
                  return ListTile(
                    leading: const Icon(Icons.badge),
                    title: Text('${a['actor_name']} (+91 ${a['actor_phone']})'),
                    subtitle: Text(
                      '${a['action']} — ${a['detail']}\n${DateFormat('d MMM, h:mm a').format(dt)}',
                    ),
                  );
                },
              ),
      ),
    );
  }
}
