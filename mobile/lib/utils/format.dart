import 'package:intl/intl.dart';

final _cop = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

String fmtMoney(num n) => _cop.format(n);

String fmtDate(String iso) {
  try {
    return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}
