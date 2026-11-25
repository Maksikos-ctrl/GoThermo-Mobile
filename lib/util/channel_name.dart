/// Turns what was typed into a channel name: no "#", no spaces, lower case.
String channelNameFrom(String input) {
  var s = input.trim().toLowerCase();
  while (s.startsWith('#')) {
    s = s.substring(1);
  }
  s = s.replaceAll(RegExp(r'\s+'), '-');
  if (s.length > 40) s = s.substring(0, 40);
  return s;
}

/// Why [name] cannot be used, or null when it is fine.
String? channelNameProblem(String name) {
  if (name.isEmpty) return 'Please enter a channel name';
  if (name.startsWith('dm_')) return 'That name is reserved';
  if (!RegExp(r'^[a-z0-9_\-]+$').hasMatch(name)) return 'Use letters, numbers, - and _ only';
  return null;
}
