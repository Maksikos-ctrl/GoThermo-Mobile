/// Lenient readers for server JSON: a wrong or missing value becomes an empty
/// one instead of an exception, so one odd field never breaks a whole screen.
String str(Object? v) => v is String ? v : '';

bool flag(Object? v) => v is bool && v;

int whole(Object? v) => v is num ? v.toInt() : 0;
