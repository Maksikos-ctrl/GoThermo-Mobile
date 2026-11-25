/// Why a message can be reported: the ids the server knows and the words the
/// web app shows for them.
const reportReasons = <({String id, String label})>[
  (id: 'spam', label: 'Spam'),
  (id: 'nsfw', label: 'Inappropriate / NSFW'),
  (id: 'harassment', label: 'Harassment'),
  (id: 'malicious', label: 'Malicious link or file'),
  (id: 'other', label: 'Something else'),
];
