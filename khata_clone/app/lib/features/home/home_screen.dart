import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/lang.dart';
import '../../core/state.dart';
import '../customers/customer_detail_screen.dart';
import '../staff/staff_screen.dart';
import '../bills/bills_screen.dart';
import '../collections/collections_screen.dart';
import '../safety/recycle_screen.dart';
import '../safety/backup_screen.dart';
import '../money/dashboard_screen.dart';
import '../money/expenses_screen.dart';
import '../money/cashbook_screen.dart';
import '../bills/inventory_screen.dart';
import '../business/refer_screen.dart';
import '../business/business_card_screen.dart';
import '../business/business_profile_screen.dart';

/// Home: cashbook summary + customer khata list + search.
///
/// Thumb-first layout: primary destinations live in the bottom bar
/// (Khata / Bills / Collections / More) instead of a crowded AppBar;
/// every customer row carries one-tap Give/Get shortcuts so recording
/// an entry skips a navigation round-trip.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KhataState>().refresh();
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  void _openDetail(int customerId, {String? initialEntry}) {
    final khata = context.read<KhataState>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(
          customerId: customerId,
          initialEntry: initialEntry,
        ),
      ),
    ).then((_) {
      if (context.mounted) {
        khata.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final khata = context.watch<KhataState>();
    final book = context.watch<BookState>();
    final cash = khata.summary?['cashbook'];
    final q = searchCtrl.text.toLowerCase();
    final list = khata.customers
        .where(
          (c) =>
              q.isEmpty ||
              (c['name'] as String).toLowerCase().contains(q) ||
              (c['phone'] as String).contains(q),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(book.label)),
      body: RefreshIndicator(
        onRefresh: () => khata.refresh(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (!book.isOwner)
              Card(
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: const Icon(Icons.badge),
                  title: Text('Viewing as ${book.role}'),
                  subtitle: const Text('Entries you make go to this book.'),
                ),
              ),
            if (context.watch<AuthState>().staffBooks.isNotEmpty)
              _bookSwitcher(context, book),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: book.can('totals')
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _stat(
                            tr(context, 'you_give'),
                            '₹${cash?['credit'] ?? 0}',
                            Colors.red,
                          ),
                          _stat(
                            tr(context, 'you_get'),
                            '₹${cash?['debit'] ?? 0}',
                            Colors.green,
                          ),
                          _stat(
                            tr(context, 'net'),
                            '₹${((cash?['credit'] ?? 0) - (cash?['debit'] ?? 0))}',
                            Colors.blue,
                          ),
                        ],
                      )
                    : const Text(
                        'Totals are hidden for your role.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr(context, 'search_customer'),
                border: const OutlineInputBorder(),
                suffixIcon: searchCtrl.text.isNotEmpty
                    ? IconButton(
                        tooltip: tr(context, 'cancel'),
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (khata.loading)
              const Center(child: CircularProgressIndicator())
            else if (khata.error != null)
              Center(
                child: Column(
                  children: [
                    Text(
                      khata.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    TextButton(
                      onPressed: () => khata.refresh(),
                      child: Text(tr(context, 'retry')),
                    ),
                  ],
                ),
              )
            else if (list.isEmpty)
              _emptyState(context, book, q.isNotEmpty)
            else
              ...list.map((c) => _customerTile(context, book, c)),
          ],
        ),
      ),
      floatingActionButton: book.can('add')
          ? FloatingActionButton.extended(
              onPressed: () => _addCustomerDialog(context),
              label: Text(tr(context, 'add_customer')),
              icon: const Icon(Icons.person_add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        onTap: (i) {
          if (i == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillsScreen()),
            );
          } else if (i == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CollectionsScreen()),
            );
          } else if (i == 3) {
            _moreSheet(context, book);
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.book),
            label: tr(context, 'khata_tab'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long),
            label: tr(context, 'bills_invoices'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.payments),
            label: tr(context, 'collections'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.more_horiz),
            label: tr(context, 'more'),
          ),
        ],
      ),
    );
  }

  Widget _bookSwitcher(BuildContext context, BookState book) {
    final auth = context.watch<AuthState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int?>(
            value: book.ownerId,
            hint: const Text('Switch book'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('My khata (owner)'),
              ),
              ...auth.staffBooks.map(
                (b) => DropdownMenuItem<int?>(
                  value: b['owner_id'] as int,
                  child: Text(
                    '${b['owner_business'] ?? 'Staff book'} (${b['role']})',
                  ),
                ),
              ),
            ],
            onChanged: (v) {
              final bk = context.read<BookState>();
              final kh = context.read<KhataState>();
              if (v == null) {
                bk.useOwnBook();
              } else {
                bk.useStaffBook(
                  (auth.staffBooks.firstWhere(
                    (b) => b['owner_id'] == v,
                  ) as Map).cast<String, dynamic>(),
                );
              }
              kh.refresh();
            },
          ),
        ),
      ),
    );
  }

  Widget _customerTile(
    BuildContext context,
    BookState book,
    Map<String, dynamic> c,
  ) {
    final bal = (c['balance'] as num?) ?? 0;
    final id = c['id'] as int;
    return ListTile(
      leading: CircleAvatar(
        child: Text(
          (c['name'] as String).isNotEmpty ? (c['name'] as String)[0] : '?',
        ),
      ),
      title: Text(c['name']),
      subtitle: Text(c['phone'] ?? ''),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '₹$bal',
            style: TextStyle(
              color: bal >= 0 ? Colors.red : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (book.can('add')) ...[
            IconButton(
              tooltip: tr(context, 'give_credit'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward, color: Colors.red),
              onPressed: () => _openDetail(id, initialEntry: 'CREDIT'),
            ),
            IconButton(
              tooltip: tr(context, 'receive_debit'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward, color: Colors.green),
              onPressed: () => _openDetail(id, initialEntry: 'DEBIT'),
            ),
          ],
        ],
      ),
      onTap: () => _openDetail(id),
    );
  }

  Widget _emptyState(BuildContext context, BookState book, bool searching) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off : Icons.group_add,
            size: 56,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            searching
                ? '“${searchCtrl.text}” — ${tr(context, 'no_entries')}'
                : tr(context, 'no_customers_yet'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (!searching) ...[
            const SizedBox(height: 4),
            Text(
              tr(context, 'tap_plus_to_add'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            if (book.can('add')) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _addCustomerDialog(context),
                icon: const Icon(Icons.person_add),
                label: Text(tr(context, 'add_customer')),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Everything secondary lives here — one thumb-reachable sheet with
  /// icons + labels, instead of a cramped AppBar overflow menu.
  void _moreSheet(BuildContext context, BookState book) {
    final lang = context.read<LanguageState>();
    void go(Widget screen) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.insights),
                title: Text(tr(context, 'dashboard')),
                onTap: () => go(const DashboardScreen()),
              ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: Text(tr(context, 'cashbook')),
              onTap: () => go(const CashBookScreen()),
            ),
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.wallet),
                title: Text(tr(context, 'expenses')),
                onTap: () => go(const ExpensesScreen()),
              ),
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.inventory_2),
                title: Text(tr(context, 'inventory')),
                onTap: () => go(const InventoryScreen()),
              ),
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.group),
                title: Text(tr(context, 'staff_access')),
                onTap: () => go(const StaffScreen()),
              ),
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: Text(tr(context, 'refer_earn')),
                onTap: () => go(const ReferScreen()),
              ),
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.contact_mail),
                title: Text(tr(context, 'business_card')),
                onTap: () => go(const BusinessCardScreen()),
              ),
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.store),
                title: Text(tr(context, 'business_profile')),
                onTap: () => go(const BusinessProfileScreen()),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr(context, 'recycle_bin')),
              onTap: () => go(const RecycleScreen()),
            ),
            if (book.isOwner)
              ListTile(
                leading: const Icon(Icons.backup),
                title: Text(tr(context, 'backup_restore')),
                onTap: () => go(const BackupScreen()),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('English'),
              trailing: lang.code == 'en' ? const Icon(Icons.check) : null,
              onTap: () {
                lang.setCode('en');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('हिन्दी'),
              trailing: lang.code == 'hi' ? const Icon(Icons.check) : null,
              onTap: () {
                lang.setCode('hi');
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                tr(context, 'logout'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => _confirmLogout(context),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final auth = context.read<AuthState>();
    final book = context.read<BookState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'logout_confirm_title')),
        content: Text(tr(ctx, 'logout_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, 'cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx); // dialog
              Navigator.pop(context); // sheet
              book.useOwnBook();
              auth.logout();
            },
            child: Text(
              tr(ctx, 'logout'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.grey)),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    ],
  );

  void _addCustomerDialog(BuildContext context) {
    final name = TextEditingController();
    final phone = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'add_customer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (name.text.trim().isEmpty) {
                messenger.showSnackBar(
                  SnackBar(content: Text(tr(context, 'name_required'))),
                );
                return;
              }
              final khata = context.read<KhataState>();
              final ok = await khata.addCustomer(
                name.text.trim(),
                phone.text.trim(),
              );
              if (context.mounted) {
                Navigator.pop(context);
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(khata.error ?? 'Failed to add customer'),
                    ),
                  );
                }
              }
            },
            child: Text(tr(context, 'save')),
          ),
        ],
      ),
    );
  }
}
