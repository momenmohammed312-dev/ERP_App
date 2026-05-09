import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  print('Resetting tamper detection flag...');

  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('last_known_date_encrypted');

  print('✅ Reset complete. Customer can restart app.');
}
