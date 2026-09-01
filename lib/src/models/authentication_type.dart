class AuthenticationType {
  final String id;
  final String code;
  final String name;
  final String description;
  final int displayOrder;

  AuthenticationType({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.displayOrder,
  });

  factory AuthenticationType.fromJson(Map<String, dynamic> json) {
    return AuthenticationType(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      displayOrder: json['displayOrder'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthenticationType &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
