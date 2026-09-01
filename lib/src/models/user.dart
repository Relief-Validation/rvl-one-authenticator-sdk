class OneAuthUser {
  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? nid;
  final String? dob;
  final String? accountNumber;
  final String? profileImageUrl;
  final String? token;
  final String? pin;
  final String? preferredAuthenticationType;

  OneAuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.phoneNumber,
    this.nid,
    this.dob,
    this.accountNumber,
    this.profileImageUrl,
    this.token,
    this.pin,
    this.preferredAuthenticationType,
  });

  factory OneAuthUser.fromJson(Map<String, dynamic> json) {
    return OneAuthUser(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      nid: json['nid'],
      dob: json['dob'],
      accountNumber: json['accountNumber'],
      profileImageUrl: json['profileImageUrl'],
      token: json['token'],
      pin: json['pin'],
      preferredAuthenticationType: json['preferredAuthenticationType'],
    );
  }

  OneAuthUser copyWith({
    String? id,
    String? name,
    String? email,
    String? phoneNumber,
    String? nid,
    String? dob,
    String? accountNumber,
    String? profileImageUrl,
    String? token,
    String? pin,
    String? preferredAuthenticationType,
  }) {
    return OneAuthUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      nid: nid ?? this.nid,
      dob: dob ?? this.dob,
      accountNumber: accountNumber ?? this.accountNumber,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      token: token ?? this.token,
      pin: pin ?? this.pin,
      preferredAuthenticationType: preferredAuthenticationType ?? this.preferredAuthenticationType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'nid': nid,
      'dob': dob,
      'accountNumber': accountNumber,
      'profileImageUrl': profileImageUrl,
      'token': token,
      'pin': pin,
      'preferredAuthenticationType': preferredAuthenticationType,
    };
  }
}
