import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal EN/HI string table (the original ships 7+ locales; this proves the
/// pattern — add more maps to extend). Persisted across launches.
const Map<String, String> _en = {
  'login_title': 'Login with your mobile number',
  'login_sub':
      'Use the same number + password on any device to sync your books.',
  'phone_label': 'Mobile number',
  'continue': 'Continue',
  'password_label': 'Password (min 8 characters)',
  'login_btn': 'Login',
  'register_btn': 'Create account',
  'have_account': 'Already have an account? Log in',
  'new_here': 'New here? Create account',
  'send_otp': 'Send OTP',
  'otp_title': 'Enter OTP',
  'verify_login': 'Verify & Login',
  'resend_otp': 'Resend OTP',
  'search_customer': 'Search customer',
  'add_customer': 'Add customer',
  'you_give': 'You give',
  'you_get': 'You get',
  'net': 'Net',
  'give_credit': 'Give (CREDIT)',
  'receive_debit': 'Receive (DEBIT)',
  'staff_access': 'Staff & access',
  'bills_invoices': 'Bills & invoices',
  'collections': 'Collections',
  'recycle_bin': 'Recycle bin',
  'backup_restore': 'Backup & restore',
  'logout': 'Logout',
  'more': 'More',
  'khata_tab': 'Khata',
  'no_customers_yet': 'No customers yet',
  'tap_plus_to_add': 'Tap + to add your first customer',
  'retry': 'Retry',
  'cancel': 'Cancel',
  'logout_confirm_title': 'Log out?',
  'logout_confirm_msg': 'You will need your password to log back in.',
  'amount_invalid': 'Enter an amount greater than zero.',
  'name_required': 'Name is required.',
  'language': 'Language',
  'dashboard': 'Dashboard',
  'expenses': 'Expenses',
  'inventory': 'Inventory',
  'cashbook': 'Cash book',
  'refer_earn': 'Refer & earn',
  'business_card': 'Business card',
  'business_profile': 'Business profile',
  'copy_code': 'Copy code',
  'share_code': 'Share code',
  'friends_joined': 'Friends joined',
  'total_earned': 'Total earned',
  'bonus_per_friend': 'Bonus per friend',
  'claim_code': 'Have a friend code? Claim your bonus',
  'claim': 'Claim',
  'claimed_bonus': 'Bonus added! You both earned ₹',
  'scan_this_card': 'Scan this card',
  'share_card': 'Share card',
  'no_entries': 'No entries for this day',
  'day_book': 'Day book',
  'today': 'Today',
  'you_gave_day': 'Given today',
  'you_received_day': 'Received today',
  'sms_on_txn': 'Send SMS on every transaction',
  'edit_profile': 'Edit business profile',
  'save': 'Save',
  'saved': 'Saved',
};

const Map<String, String> _hi = {
  'login_title': 'अपने मोबाइल नंबर से लॉगिन करें',
  'login_sub':
      'किसी भी डिवाइस पर वही नंबर + पासवर्ड इस्तेमाल करें — आपका बही-खाता सिंक होगा।',
  'phone_label': 'मोबाइल नंबर',
  'continue': 'आगे बढ़ें',
  'password_label': 'पासवर्ड (कम से कम 8 अक्षर)',
  'login_btn': 'लॉगिन',
  'register_btn': 'खाता बनाएँ',
  'have_account': 'पहले से खाता है? लॉगिन करें',
  'new_here': 'नए हैं? खाता बनाएँ',
  'send_otp': 'OTP भेजें',
  'otp_title': 'OTP दर्ज करें',
  'verify_login': 'सत्यापित करें और लॉगिन करें',
  'resend_otp': 'OTP पुनः भेजें',
  'search_customer': 'ग्राहक खोजें',
  'add_customer': 'ग्राहक जोड़ें',
  'you_give': 'आपने दिया',
  'you_get': 'आपको मिला',
  'net': 'शेष',
  'give_credit': 'उधार दें',
  'receive_debit': 'भुगतान लें',
  'staff_access': 'स्टाफ और एक्सेस',
  'bills_invoices': 'बिल और चालान',
  'collections': 'वसूली',
  'recycle_bin': 'रिसायकल बिन',
  'backup_restore': 'बैकअप और रिस्टोर',
  'logout': 'लॉगआउट',
  'more': 'अधिक',
  'khata_tab': 'खाता',
  'no_customers_yet': 'अभी कोई ग्राहक नहीं',
  'tap_plus_to_add': 'पहला ग्राहक जोड़ने के लिए + दबाएँ',
  'retry': 'पुनः प्रयास',
  'cancel': 'रद्द करें',
  'logout_confirm_title': 'लॉगआउट करें?',
  'logout_confirm_msg': 'वापस लॉगिन के लिए पासवर्ड चाहिए होगा।',
  'amount_invalid': 'शून्य से बड़ी राशि दर्ज करें।',
  'name_required': 'नाम ज़रूरी है।',
  'language': 'भाषा',
  'dashboard': 'डैशबोर्ड',
  'expenses': 'खर्च',
  'inventory': 'स्टॉक / इन्वेंटरी',
  'cashbook': 'कैश बुक',
  'refer_earn': 'रेफर और कमाएँ',
  'business_card': 'बिज़नेस कार्ड',
  'business_profile': 'व्यापार प्रोफ़ाइल',
  'copy_code': 'कोड कॉपी करें',
  'share_code': 'कोड साझा करें',
  'friends_joined': 'जुड़े हुए मित्र',
  'total_earned': 'कुल कमाई',
  'bonus_per_friend': 'प्रति मित्र बोनस',
  'claim_code': 'दोस्त का कोड है? बोनस क्लेम करें',
  'claim': 'क्लेम करें',
  'claimed_bonus': 'बोनस जुड़ गया! आप दोनों ने कमाया ₹',
  'scan_this_card': 'यह कार्ड स्कैन करें',
  'share_card': 'कार्ड साझा करें',
  'no_entries': 'इस दिन कोई एंट्री नहीं',
  'day_book': 'डे बुक',
  'today': 'आज',
  'you_gave_day': 'आज दिया',
  'you_received_day': 'आज मिला',
  'sms_on_txn': 'हर लेन-देन पर SMS भेजें',
  'edit_profile': 'व्यापार प्रोफ़ाइल बदलें',
  'save': 'सेव करें',
  'saved': 'सेव हो गया',
};

class LanguageState extends ChangeNotifier {
  String code = 'en';

  /// True once the user has explicitly picked a language (first-run
  /// picker). Until then the app asks instead of assuming English.
  bool picked = false;

  LanguageState() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    code = prefs.getString('lang') ?? 'en';
    picked = prefs.getBool('lang_picked') ?? false;
    notifyListeners();
  }

  Future<void> setCode(String c) async {
    code = c;
    picked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', c);
    await prefs.setBool('lang_picked', true);
    notifyListeners();
  }

  String t(String key) => (code == 'hi' ? _hi : _en)[key] ?? _en[key] ?? key;
}

String tr(BuildContext context, String key) =>
    context.watch<LanguageState>().t(key);
