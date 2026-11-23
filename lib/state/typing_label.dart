/// The line above the composer, worded like the web app.
String typingLabel(List<String> names) {
  switch (names.length) {
    case 0:
      return '';
    case 1:
      return '${names[0]} is typing…';
    case 2:
      return '${names[0]} and ${names[1]} are typing…';
    case 3:
      return '${names[0]}, ${names[1]} and ${names[2]} are typing…';
    default:
      return 'Several people are typing…';
  }
}
