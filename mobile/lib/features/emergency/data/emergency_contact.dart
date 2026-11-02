class EmergencyContact {
  const EmergencyContact({
    required this.name,
    this.phone,
    this.email,
    this.relationship,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? relationship;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim() ?? '';
    final phone = (json['phone'] as String?)?.trim();
    final email = (json['email'] as String?)?.trim();
    final relationship = (json['relationship'] as String?)?.trim();

    return EmergencyContact(
      name: name,
      phone: (phone == null || phone.isEmpty) ? null : phone,
      email: (email == null || email.isEmpty) ? null : email,
      relationship: (relationship == null || relationship.isEmpty)
          ? null
          : relationship,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'phone': phone,
      'email': email,
      'relationship': relationship,
    };
  }
}
