class User {
  final String id;
  final String email;
  final String fullName;
  final String role; // 'parent' or 'child'
  final String? familyId;
  final int focusCoins;
  final List<String> stickers;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.familyId,
    this.focusCoins = 0,
    this.stickers = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? 'child',
      familyId: json['family_id'],
      focusCoins: json['focus_coins'] ?? 0,
      stickers: (json['stickers'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role,
      'family_id': familyId,
      'focus_coins': focusCoins,
      'stickers': stickers,
    };
  }

  bool get isParent => role == 'parent';
  bool get isChild => role == 'child';
}
