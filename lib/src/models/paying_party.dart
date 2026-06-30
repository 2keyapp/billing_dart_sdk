import 'jwt_payload_keys.dart';

/// Paying party (org) that owns the subscriptions — from license JWT `paying_party`.
class PayingParty {
  const PayingParty({
    required this.id,
    required this.identityProvider,
    required this.identitySubject,
    required this.billingEmail,
    this.organizationName,
  });

  final String id;
  final String identityProvider;
  final String identitySubject;
  final String billingEmail;
  final String? organizationName;

  String get ssoId => identitySubject;

  factory PayingParty.fromJson(Map<String, dynamic> json) {
    final id = getKey(json, 'id', 'id');
    final identityProvider = getKey(
      json,
      'identity_provider',
      'identityProvider',
    );
    final identitySubject = getKey(json, 'identity_subject', 'identitySubject');
    final ssoIdLegacy = getKey(json, 'sso_id', 'ssoId');
    final billingEmail = getKey(json, 'billing_email', 'billingEmail');
    if (id is! String || id.isEmpty) {
      throw FormatException('paying_party.id required.');
    }
    if (billingEmail is! String) {
      throw FormatException('paying_party.billing_email required.');
    }
    final provider = identityProvider is String && identityProvider.isNotEmpty
        ? identityProvider
        : (ssoIdLegacy is String && ssoIdLegacy.isNotEmpty ? 'legacy' : null);
    final subject = identitySubject is String && identitySubject.isNotEmpty
        ? identitySubject
        : (ssoIdLegacy is String ? ssoIdLegacy : null);
    if (provider == null || subject == null) {
      throw FormatException(
        'paying_party: identity_provider and identity_subject required (or legacy sso_id).',
      );
    }
    final org = getKey(json, 'organization_name', 'organizationName');
    return PayingParty(
      id: id,
      identityProvider: provider,
      identitySubject: subject,
      billingEmail: billingEmail,
      organizationName: org is String ? org : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PayingParty &&
          id == other.id &&
          identityProvider == other.identityProvider &&
          identitySubject == other.identitySubject &&
          billingEmail == other.billingEmail &&
          organizationName == other.organizationName;

  @override
  int get hashCode => Object.hash(
        id,
        identityProvider,
        identitySubject,
        billingEmail,
        organizationName,
      );
}
