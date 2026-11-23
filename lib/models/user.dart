import 'json.dart';

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

  bool get isOnline => status == 'online';

  User copyWith({String? status, String? avatar, bool clearAvatar = false}) => User(
        id: id,
        username: username,
        email: email,
        status: status ?? this.status,
        avatar: clearAvatar ? null : (avatar ?? this.avatar),
        isAdmin: isAdmin,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'status': status,
        'avatar': avatar ?? '',
        'isAdmin': isAdmin,
      };

  factory User.fromJson(Map<String, dynamic> json) {
    final avatar = str(json['avatar']);
    return User(
      id: str(json['id']),
      username: str(json['username']),
      email: str(json['email']),
      status: json['status'] is String ? json['status'] as String : 'offline',
      avatar: avatar.isEmpty ? null : avatar,
      isAdmin: flag(json['isAdmin']),
    );
  }
}

/// A signed-in person and the token that proves it.
class Session {
  const Session({required this.token, required this.user});

  final String token;
  final User user;
}
