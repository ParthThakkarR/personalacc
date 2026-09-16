import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Staged login flow.
/// PASSWORD MODE (active, zero SMS cost):
/// phone → password → (new? profile → pinSetup) → pinUnlock? → home
/// OTP MODE (parked, see seam below): phone → otp → …
enum AuthStage { checking, phone, password, otp, profile, pinSetup, pinUnlock, home }

/// Auth state machine: loading/error/data tri-state per step, resend countdown
/// (cf. `login_waiting_for_code`), attempt + lockout surfacing (cf. AppLock).
class AuthState extends ChangeNotifier {
  AuthState(this.api);
  final ApiClient api;

  AuthStage stage = AuthStage.checking;
  bool loading = false;
  String? error;
  String phone = '';
  int resendAfterS = 0;
  bool isNew = false;
  Map<String, dynamic>? user;
  List<dynamic> staffBooks = [];
  Timer? _timer;

  bool get profileComplete => user?['profile_complete'] == true;
  bool get hasPin => user?['has_pin'] == true;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (resendAfterS > 0) {
      resendAfterS--;
      notifyListeners();
    } else {
      _timer?.cancel();
    }
  }

  void _cooldown(int s) {
    _timer?.cancel();
    resendAfterS = s;
    if (s > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  static String friendly(Object e) {
    if (e is SessionExpired) return e.toString();
    if (e is ApiException) {
      switch (e.code) {
        case 'resend_cooldown':
          return 'Please wait before requesting a new OTP.';
        case 'too_many_requests':
          return 'Too many OTP requests. Try again in 15 minutes.';
        case 'invalid_otp':
          return 'Wrong OTP. Please try again.';
        case 'expired_otp':
          return 'OTP expired. Please request a new one.';
        case 'too_many_attempts':
          return 'Too many wrong attempts. Request a fresh OTP.';
        case 'invalid_pin':
          return 'Wrong PIN. Please try again.';
        case 'pin_locked':
          return 'Too many wrong PINs. App locked — try later.';
        case 'invalid_current_pin':
          return 'Current PIN is incorrect.';
        case 'pin_not_set':
          return 'PIN is not set on this account.';
        case 'invalid_credentials':
          return 'Wrong mobile number or password.';
        case 'user_exists':
          return 'This number already has an account. Please log in.';
        case 'weak_password':
          return 'Password must be at least 8 characters.';
        case 'invalid_code':
          return 'That referral code was not found.';
        case 'own_code':
          return 'You cannot claim your own code.';
        case 'already_referred':
          return 'You have already claimed a referral bonus.';
      }
      return 'Request failed (${e.code}).';
    }
    return e.toString();
  }

  Future<void> init() async {
    stage = AuthStage.checking;
    notifyListeners();
    await api.init();
    if (!api.isLoggedIn) {
      stage = AuthStage.phone;
      notifyListeners();
      return;
    }
    try {
      final j = await api.get('/auth/me') as Map;
      user = Map<String, dynamic>.from(j['user'] as Map);
      staffBooks = ((j['staff_books'] as List?) ?? []).cast<dynamic>();
      _routePostLogin();
    } catch (_) {
      stage = AuthStage.phone;
    }
    notifyListeners();
  }

  void _routePostLogin() {
    if (!profileComplete) {
      stage = AuthStage.profile;
    } else if (hasPin) {
      stage = AuthStage.pinUnlock;
    } else {
      stage = AuthStage.home;
    }
  }

  bool validPhone(String p) => RegExp(r'^[0-9]{10}$').hasMatch(p);
  bool validPassword(String p) => p.length >= 8;

  /// Step 1 → 2 (password mode): remember the phone, move to password entry.
  /// No network call: account existence is resolved by login-vs-register.
  bool goToPassword(String p) {
    if (!validPhone(p)) {
      error = 'Enter a valid 10-digit mobile number.';
      notifyListeners();
      return false;
    }
    phone = p;
    error = null;
    stage = AuthStage.password;
    notifyListeners();
    return true;
  }

  Future<bool> _finishPasswordAuth(Map j) async {
    await api.setSession(
      access: j['access'] as String,
      refresh: j['refresh'] as String,
    );
    user = Map<String, dynamic>.from(j['user'] as Map);
    isNew = (j['is_new'] as bool?) ?? false;
    staffBooks = ((j['staff_books'] as List?) ?? []).cast<dynamic>();
    _routePostLogin();
    return true;
  }

  /// Returning device (or second device, same number): syncs the same books.
  Future<bool> loginWithPassword(String password) async {
    if (phone.isEmpty || password.isEmpty) {
      error = 'Enter your password.';
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.postPublic('/auth/login', {
        'phone': phone,
        'password': password,
      }) as Map;
      return await _finishPasswordAuth(j);
    } catch (e) {
      error = friendly(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// First device: creates the account (409 user_exists → switch to login).
  Future<bool> registerWithPassword(String password) async {
    if (phone.isEmpty || !validPassword(password)) {
      error = 'Password must be at least 8 characters.';
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.postPublic('/auth/register', {
        'phone': phone,
        'password': password,
      }) as Map;
      return await _finishPasswordAuth(j);
    } catch (e) {
      error = friendly(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /* --- OTP seam (PARKED — SMS flow, re-enable with routes/auth.js OTP block
   * and otp_screen.dart call sites when an SMS provider is funded).
   * Preserved intact below; OtpScreen is unrouted while parked.

  Future<bool> requestOtp(String p) async {
    if (!validPhone(p)) {
      error = 'Enter a valid 10-digit mobile number.';
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.postPublic('/auth/request-otp', {'phone': p}) as Map;
      phone = p;
      _cooldown((j['resend_after_s'] as num?)?.toInt() ?? 60);
      stage = AuthStage.otp;
      return true;
    } catch (e) {
      error = friendly(e);
      if (e is ApiException && e.code == 'resend_cooldown') {
        try {
          final m = RegExp(r'resend_after_s[^0-9]*([0-9]+)')
              .firstMatch(e.body)
              ?.group(1);
          _cooldown(int.tryParse(m ?? '') ?? 60);
        } catch (_) {}
      }
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> resendOtp() async {
    if (resendAfterS > 0 || phone.isEmpty) return false;
    return requestOtp(phone);
  }

  Future<bool> verifyOtp(String code) async {
    if (code.length < 4) {
      error = 'Enter the OTP sent to your phone.';
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.postPublic('/auth/verify-otp', {
        'phone': phone,
        'code': code,
      }) as Map;
      await api.setSession(
        access: j['access'] as String,
        refresh: j['refresh'] as String,
      );
      user = Map<String, dynamic>.from(j['user'] as Map);
      isNew = (j['is_new'] as bool?) ?? false;
      staffBooks = ((j['staff_books'] as List?) ?? []).cast<dynamic>();
      _timer?.cancel();
      resendAfterS = 0;
      _routePostLogin();
      return true;
    } catch (e) {
      error = friendly(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
  --- end OTP parked block ---
  */

  void backToPhone() {
    _timer?.cancel();
    resendAfterS = 0;
    stage = AuthStage.phone;
    error = null;
    notifyListeners();
  }

  Future<bool> saveProfile({
    required String name,
    required String business,
    String? category,
  }) async {
    if (name.trim().isEmpty || business.trim().isEmpty) {
      error = 'Name and business name are required.';
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.patch('/auth/profile', {
        'name': name.trim(),
        'business_name': business.trim(),
        if (category != null && category.isNotEmpty)
          'business_category': category,
      }) as Map;
      user = Map<String, dynamic>.from(j['user'] as Map);
      stage = hasPin ? AuthStage.home : AuthStage.pinSetup;
      return true;
    } catch (e) {
      error = friendly(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Re-fetch the profile after an in-app edit (business profile screen).
  Future<void> refreshUser() async {
    try {
      final j = await api.get('/auth/me') as Map;
      user = Map<String, dynamic>.from(j['user'] as Map);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> setPin(String pin, {String? currentPin}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await api.post('/auth/pin-set', {
        'pin': pin,
        if (currentPin != null) 'current_pin': currentPin,
      });
      final j = await api.get('/auth/me') as Map;
      user = Map<String, dynamic>.from(j['user'] as Map);
      stage = AuthStage.home;
      return true;
    } catch (e) {
      error = friendly(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> unlockPin(String pin) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await api.post('/auth/pin-verify', {'pin': pin});
      stage = AuthStage.home;
      return true;
    } catch (e) {
      error = friendly(e);
      if (e is ApiException && e.code == 'pin_locked') {
        try {
          final m = RegExp(r'retry_after_s[^0-9]*([0-9]+)')
              .firstMatch(e.body)
              ?.group(1);
          error = 'App locked. Try again in ${m ?? '?'} seconds.';
        } catch (_) {}
      }
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await api.postPublic('/auth/logout', {});
    } catch (_) {}
    await api.clear();
    user = null;
    staffBooks = [];
    phone = '';
    _timer?.cancel();
    resendAfterS = 0;
    stage = AuthStage.phone;
    notifyListeners();
  }
}

/// Khata state: customers + transactions + summary.
class KhataState extends ChangeNotifier {
  KhataState(this.api);
  final ApiClient api;
  List<dynamic> customers = [];
  Map<String, dynamic>? summary;
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final c = await api.get('/customers') as Map;
      customers = (c['customers'] as List).cast<dynamic>();
      try {
        summary = Map<String, dynamic>.from(
          await api.get('/reports/summary') as Map,
        );
      } catch (_) {
        // Staff without the totals permission still get their khata list;
        // the totals card renders its role-gated message instead.
        summary = null;
      }
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> addCustomer(String name, String phone) async {
    try {
      await api.post('/customers', {'name': name, 'phone': phone});
      await refresh();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> addTxn(
    int customerId,
    String kind,
    int amount,
    String note,
  ) async {
    try {
      await api.post('/transactions', {
        'customer_id': customerId,
        'kind': kind,
        'amount': amount,
        'note': note,
      });
      await refresh();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }
}

/// Active book context: own khata or a staff book (cf. accesscontrol roles).
/// Drives the X-Book-Owner-Id header and permission-gates the UI.
class BookState extends ChangeNotifier {
  BookState(this.api);
  final ApiClient api;

  int? ownerId; // null = own book
  String role = 'owner';
  List<String> perms = const ['view', 'add', 'edit', 'totals', 'manage_staff'];
  String label = 'My khata';
  List<dynamic> staff = [];
  List<dynamic> activity = [];
  bool loading = false;
  String? error;

  static const allRoles = ['manager', 'entry', 'viewer'];

  bool get isOwner => ownerId == null;
  bool can(String p) => perms.contains(p);

  void useOwnBook() {
    ownerId = null;
    role = 'owner';
    perms = const ['view', 'add', 'edit', 'totals', 'manage_staff'];
    label = 'My khata';
    api.bookOwnerId = null;
    notifyListeners();
  }

  void useStaffBook(Map<String, dynamic> b) {
    ownerId = b['owner_id'] as int;
    role = (b['role'] as String?) ?? 'viewer';
    perms = switch (role) {
      'manager' => const ['view', 'add', 'edit', 'totals'],
      'entry' => const ['view', 'add'],
      _ => const ['view'],
    };
    label = (b['owner_business'] as String?)?.isNotEmpty == true
        ? b['owner_business'] as String
        : 'Staff book';
    api.bookOwnerId = ownerId;
    notifyListeners();
  }

  Future<void> loadStaff() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.get('/staff') as Map;
      staff = (j['staff'] as List).cast<dynamic>();
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> invite(String phone, String role) async {
    try {
      await api.post('/staff/invite', {'phone': phone, 'role': role});
      await loadStaff();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> setRole(String phone, String role) async {
    try {
      await api.post('/staff/role', {'phone': phone, 'role': role});
      await loadStaff();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> revoke(String phone) async {
    try {
      await api.post('/staff/revoke', {'phone': phone});
      await loadStaff();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> loadActivity() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.get('/staff/activity') as Map;
      activity = (j['activity'] as List).cast<dynamic>();
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// Bills + GST invoices (cf. billbook + assets/invoices).
class BillState extends ChangeNotifier {
  BillState(this.api);
  final ApiClient api;
  List<dynamic> bills = [];
  List<dynamic> slabs = [];
  bool loading = false;
  String? error;

  Future<void> loadAll() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final b = await api.get('/bills') as Map;
      bills = (b['bills'] as List).cast<dynamic>();
      final m = await api.get('/bills/meta') as Map;
      slabs = (m['slabs'] as List).cast<dynamic>();
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> detail(int id) async {
    try {
      final j = await api.get('/bills/$id') as Map;
      return Map<String, dynamic>.from(j);
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return null;
    }
  }

  Future<int?> createBill({
    required String invoiceNo,
    required int slabIndex,
    required int discount,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final j = await api.post('/bills', {
        'invoice_no': invoiceNo,
        'gst_slab_index': slabIndex,
        'discount': discount,
        'items': items,
      }) as Map;
      await loadAll();
      return j['id'] as int;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return null;
    }
  }

  Future<String?> invoiceHtml(
    int id,
    String template, {
    bool seal = false,
  }) async {
    try {
      return await api.getRaw(
        '/bills/$id/html?template=$template${seal ? '&seal=1' : ''}',
      );
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return null;
    }
  }
}

/// Collections: dues reminders + mock payment links (cf. W7).
class CollectionState extends ChangeNotifier {
  CollectionState(this.api);
  final ApiClient api;
  List<dynamic> links = [];
  List<dynamic> reminders = [];
  bool loading = false;
  String? error;

  Future<void> loadAll() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final l = await api.get('/collections/links') as Map;
      links = (l['links'] as List).cast<dynamic>();
      final r = await api.get('/collections/reminders') as Map;
      reminders = (r['reminders'] as List).cast<dynamic>();
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> createLink(int customerId, int amount) async {
    try {
      final j = await api.post('/collections/links', {
        'customer_id': customerId,
        'amount': amount,
      }) as Map;
      await loadAll();
      return Map<String, dynamic>.from(j);
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> payLink(String ref) async {
    try {
      await api.post('/collections/links/$ref/pay', {});
      await loadAll();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<int?> queueReminders(
    List<int> customerIds,
    String channel,
    String message,
  ) async {
    try {
      final j = await api.post('/collections/reminders', {
        'customer_ids': customerIds,
        'channel': channel,
        'message': message,
      }) as Map;
      await loadAll();
      return j['queued'] as int?;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return null;
    }
  }
}

/// Recycle bin + backup/restore (cf. recyclebin + backuprestore).
class RecycleState extends ChangeNotifier {
  RecycleState(this.api);
  final ApiClient api;
  List<dynamic> customers = [];
  List<dynamic> transactions = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.get('/recycle') as Map;
      customers = (j['customers'] as List).cast<dynamic>();
      transactions = (j['transactions'] as List).cast<dynamic>();
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> _act(String path, {bool isDelete = false}) async {
    try {
      if (isDelete) {
        await api.del(path);
      } else {
        await api.post(path, {});
      }
      await load();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> restoreCustomer(int id) =>
      _act('/recycle/customers/$id/restore');
  Future<bool> restoreTxn(int id) => _act('/recycle/transactions/$id/restore');
  Future<bool> purgeCustomer(int id) =>
      _act('/recycle/customers/$id/permanent', isDelete: true);
  Future<bool> purgeTxn(int id) =>
      _act('/recycle/transactions/$id/permanent', isDelete: true);

  Future<Map<String, dynamic>?> export() async {
    try {
      final j = await api.get('/backup/export') as Map;
      return Map<String, dynamic>.from(j);
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> import(Map<String, dynamic> payload) async {
    try {
      await api.post('/backup/import', payload);
      await load();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }
}

/// Expenses tracker (cf. finance/expenses). Soft-delete → recycle bin.
class ExpenseState extends ChangeNotifier {
  ExpenseState(this.api);
  final ApiClient api;
  List<dynamic> expenses = [];
  int total = 0;
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.get('/expenses') as Map;
      expenses = (j['expenses'] as List).cast<dynamic>();
      total = (j['total'] as num?)?.toInt() ?? 0;
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> add(int amount, String note, String category) async {
    try {
      await api.post('/expenses', {
        'amount': amount,
        'note': note,
        'category': category,
      });
      await refresh();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await api.del('/expenses/$id');
      await refresh();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }
}

/// Inventory item master (cf. inventory module). Feeds bill creation.
class ItemState extends ChangeNotifier {
  ItemState(this.api);
  final ApiClient api;
  List<dynamic> items = [];
  int totalStockValue = 0;
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final j = await api.get('/items') as Map;
      items = (j['items'] as List).cast<dynamic>();
      totalStockValue = (j['total_stock_value'] as num?)?.toInt() ?? 0;
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> add(Map<String, dynamic> item) async {
    try {
      await api.post('/items', item);
      await refresh();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> update(int id, Map<String, dynamic> patch) async {
    try {
      await api.patch('/items/$id', patch);
      await refresh();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await api.del('/items/$id');
      await refresh();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }
}

/// Owner dashboard/insights (cf. userdashboard).
class DashboardState extends ChangeNotifier {
  DashboardState(this.api);
  final ApiClient api;
  Map<String, dynamic>? data;
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      data = Map<String, dynamic>.from(
        await api.get('/reports/dashboard') as Map,
      );
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// Engagement + identity (Phases 8-10): refer & earn, business card / QR,
/// txn-SMS preference, and the day-book (cash register) report.
class BusinessState extends ChangeNotifier {
  BusinessState(this.api);
  final ApiClient api;
  Map<String, dynamic>? referral;
  Map<String, dynamic>? card;
  bool txnSms = false;
  Map<String, dynamic>? daybook;
  int lastClaimBonus = 0;
  bool loading = false;
  String? error;

  Future<void> loadEngagement() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      referral = Map<String, dynamic>.from(
        await api.get('/business/referral') as Map,
      );
      card = Map<String, dynamic>.from(await api.get('/business/card') as Map);
      final prefs = await api.get('/business/preferences') as Map;
      txnSms = prefs['txn_sms'] == true;
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Returns true on success; `lastClaimBonus` holds the rewarded amount.
  Future<bool> claim(String code) async {
    try {
      final j = await api.post('/business/referral/claim', {
        'code': code.trim(),
      });
      lastClaimBonus = (j['bonus'] as num?)?.toInt() ?? 0;
      await loadEngagement();
      notifyListeners();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> setTxnSms(bool v) async {
    try {
      await api.post('/business/preferences', {'txn_sms': v});
      txnSms = v;
      notifyListeners();
      return true;
    } catch (e) {
      error = AuthState.friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> loadDaybook({String? date}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      daybook = Map<String, dynamic>.from(
        await api.get('/reports/daybook${date == null ? '' : '?date=$date'}')
            as Map,
      );
    } catch (e) {
      error = AuthState.friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
