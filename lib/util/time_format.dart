String _two(int n) => n.toString().padLeft(2, '0');

/// `14:05`
String clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// `Today`, `Yesterday` or `12 November` (with the year when it is not this year).
String dayLabel(DateTime t, DateTime now) {
  if (sameDay(t, now)) return 'Today';
  if (sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  final base = '${t.day} ${_months[t.month - 1]}';
  return t.year == now.year ? base : '$base ${t.year}';
}

/// Short stamp for lists: the time today, `Yesterday`, otherwise `12 Nov`.
String shortStamp(DateTime t, DateTime now) {
  if (sameDay(t, now)) return clock(t);
  if (sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${t.day} ${_months[t.month - 1].substring(0, 3)}';
}

/// `1.2 MB`
String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// `1:05` for a call length in seconds.
String callLength(int seconds) => '${seconds ~/ 60}:${_two(seconds % 60)}';
