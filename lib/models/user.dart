class User {
  const User({
    required this.username,
    this.id = '',
    this.email = '',
    this.status = 'offline',
    this.avatar,
    this.isAdmin = false,
  });

  final String id;
  final String username;
  final String email;
  final String status;
  final String? avatar;
  final bool isAdmin;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: (json['id'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'offline',
        avatar: json['avatar'] as String?,
        isAdmin: (json['isAdmin'] as bool?) ?? false,
      );
}

/// A signed-in person and the token that proves it.
class Session {
  const Session({required this.token, required this.user});

  final String token;
  final User user;
}
