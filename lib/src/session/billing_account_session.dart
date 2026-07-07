import '../auth/auth_user_profile.dart';
import '../auth/billing_auth_tokens.dart';
import '../models/billing_stats.dart';
import '../models/billing_token_payload.dart';

/// Persisted billing account state: auth tokens, user profile, org summary, license JWT.
class BillingAccountSession {
  const BillingAccountSession({
    required this.authTokens,
    required this.userProfile,
    this.billingStats,
    this.licenseJwt,
    this.licensePayload,
    this.licenseEtag,
    this.payingPartyIdHeader,
    this.lastLicenseSyncAt,
    this.updatedAt,
  });

  final BillingAuthTokens authTokens;
  final AuthUserProfile userProfile;
  final PayingPartyBillingStats? billingStats;
  final String? licenseJwt;
  final BillingTokenPayload? licensePayload;
  /// HTTP ETag from the last successful `GET /api/v1/license` response.
  final String? licenseEtag;
  final String? payingPartyIdHeader;
  final DateTime? lastLicenseSyncAt;
  final DateTime? updatedAt;

  String get accessToken => authTokens.accessToken;

  /// Using party: holds an assigned seat on the org subscription.
  bool get isUsingParty => billingStats?.isUsingParty ?? false;

  /// Paying party owner: token identity matches license paying party identity.
  bool get isPayingPartyOwner {
    final payload = licensePayload;
    if (payload == null) return false;
    final party = payload.payingParty;
    final provider = userProfile.identityProvider;
    if (provider != null &&
        provider.isNotEmpty &&
        party.identityProvider == provider &&
        party.identitySubject == userProfile.subject) {
      return true;
    }
    final email = userProfile.email?.trim().toLowerCase();
    final billingEmail = party.billingEmail.trim().toLowerCase();
    return email != null &&
        email.isNotEmpty &&
        userProfile.emailVerified &&
        email == billingEmail;
  }

  /// Portal management is for paying-party owners; using-party users sync only.
  bool get canOpenBillingPortal => isPayingPartyOwner;

  BillingAccountSession copyWith({
    BillingAuthTokens? authTokens,
    AuthUserProfile? userProfile,
    PayingPartyBillingStats? billingStats,
    String? licenseJwt,
    BillingTokenPayload? licensePayload,
    String? licenseEtag,
    String? payingPartyIdHeader,
    DateTime? lastLicenseSyncAt,
    DateTime? updatedAt,
  }) =>
      BillingAccountSession(
        authTokens: authTokens ?? this.authTokens,
        userProfile: userProfile ?? this.userProfile,
        billingStats: billingStats ?? this.billingStats,
        licenseJwt: licenseJwt ?? this.licenseJwt,
        licensePayload: licensePayload ?? this.licensePayload,
        licenseEtag: licenseEtag ?? this.licenseEtag,
        payingPartyIdHeader: payingPartyIdHeader ?? this.payingPartyIdHeader,
        lastLicenseSyncAt: lastLicenseSyncAt ?? this.lastLicenseSyncAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'authTokens': authTokens.toJson(),
        'userProfile': {
          'subject': userProfile.subject,
          if (userProfile.email != null) 'email': userProfile.email,
          'emailVerified': userProfile.emailVerified,
          if (userProfile.identityProvider != null)
            'identityProvider': userProfile.identityProvider,
          if (userProfile.audience != null) 'audience': userProfile.audience,
          if (userProfile.issuer != null) 'issuer': userProfile.issuer,
          if (userProfile.clientId != null) 'clientId': userProfile.clientId,
          if (userProfile.scope != null) 'scope': userProfile.scope,
        },
        if (billingStats != null)
          'billingStats': {
            'payingParty': {
              'id': billingStats!.payingParty.id,
              'organizationName': billingStats!.payingParty.organizationName,
              'billingEmail': billingStats!.payingParty.billingEmail,
            },
            'hasAssignedSeatForIdentity': billingStats!.hasAssignedSeatForIdentity,
          },
        if (licenseJwt != null) 'licenseJwt': licenseJwt,
        if (licenseEtag != null) 'licenseEtag': licenseEtag,
        if (payingPartyIdHeader != null) 'payingPartyIdHeader': payingPartyIdHeader,
        if (lastLicenseSyncAt != null)
          'lastLicenseSyncAt': lastLicenseSyncAt!.toUtc().toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  factory BillingAccountSession.fromJson(Map<String, dynamic> json) {
    final authRaw = json['authTokens'] ?? json['auth_tokens'];
    if (authRaw is! Map<String, dynamic>) {
      throw FormatException('authTokens required.');
    }
    final tokens = BillingAuthTokens.fromJson(authRaw);
    final profileRaw = json['userProfile'] ?? json['user_profile'];
    final profile = profileRaw is Map<String, dynamic>
        ? AuthUserProfile(
            subject: '${profileRaw['subject']}',
            email: profileRaw['email'] as String?,
            emailVerified: profileRaw['emailVerified'] == true,
            identityProvider: profileRaw['identityProvider'] as String?,
            audience: profileRaw['audience'] as String?,
            issuer: profileRaw['issuer'] as String?,
            clientId: profileRaw['clientId'] as String?,
            scope: profileRaw['scope'] as String?,
          )
        : AuthUserProfile.fromAccessToken(tokens.accessToken);

    PayingPartyBillingStats? stats;
    final statsRaw = json['billingStats'] ?? json['billing_stats'];
    if (statsRaw is Map<String, dynamic>) {
      final partyRaw = statsRaw['payingParty'] ?? statsRaw['paying_party'];
      if (partyRaw is Map<String, dynamic>) {
        stats = PayingPartyBillingStats(
          payingParty: PayingPartyBillingSummary.fromJson(partyRaw),
          counts: const BillingCounts(
            subscriptions: SubscriptionStatusCounts(),
            orders: OrderStatusCounts(),
            invoices: InvoiceStatusCounts(),
          ),
          hasAssignedSeatForIdentity:
              statsRaw['hasAssignedSeatForIdentity'] as bool? ?? false,
        );
      }
    }

    final updatedRaw = json['updatedAt'] ?? json['updated_at'];
    final lastSyncRaw = json['lastLicenseSyncAt'] ?? json['last_license_sync_at'];
    return BillingAccountSession(
      authTokens: tokens,
      userProfile: profile,
      billingStats: stats,
      licenseJwt: json['licenseJwt'] as String? ?? json['license_jwt'] as String?,
      licenseEtag: json['licenseEtag'] as String? ?? json['license_etag'] as String?,
      payingPartyIdHeader: json['payingPartyIdHeader'] as String?,
      lastLicenseSyncAt:
          lastSyncRaw is String ? DateTime.tryParse(lastSyncRaw) : null,
      updatedAt: updatedRaw is String ? DateTime.tryParse(updatedRaw) : null,
    );
  }
}
