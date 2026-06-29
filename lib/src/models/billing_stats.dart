/// Aggregated billing context from `GET /api/v1/subscriptions/me`.
class PayingPartyBillingStats {
  const PayingPartyBillingStats({
    required this.payingParty,
    required this.counts,
    required this.hasAssignedSeatForIdentity,
    this.upcomingBillingDate,
    this.recentInvoices = const [],
  });

  final PayingPartyBillingSummary payingParty;
  final BillingCounts counts;
  final DateTime? upcomingBillingDate;
  final bool hasAssignedSeatForIdentity;
  final List<RecentInvoiceSummary> recentInvoices;

  /// True when the authenticated identity holds an assigned seat (using party).
  bool get isUsingParty => hasAssignedSeatForIdentity;

  factory PayingPartyBillingStats.fromJson(Map<String, dynamic> json) {
    final partyRaw = json['payingParty'] ?? json['paying_party'];
    if (partyRaw is! Map<String, dynamic>) {
      throw FormatException('payingParty object required.');
    }
    final countsRaw = json['counts'];
    if (countsRaw is! Map<String, dynamic>) {
      throw FormatException('counts object required.');
    }
    final upcoming = json['upcomingBillingDate'] ?? json['upcoming_billing_date'];
    return PayingPartyBillingStats(
      payingParty: PayingPartyBillingSummary.fromJson(partyRaw),
      counts: BillingCounts.fromJson(countsRaw),
      upcomingBillingDate: _parseDateTime(upcoming),
      hasAssignedSeatForIdentity:
          json['hasAssignedSeatForIdentity'] as bool? ??
          json['has_assigned_seat_for_identity'] as bool? ??
          false,
      recentInvoices: _parseRecentInvoices(json['recentInvoices'] ?? json['recent_invoices']),
    );
  }
}

class PayingPartyBillingSummary {
  const PayingPartyBillingSummary({
    required this.id,
    required this.organizationName,
    required this.billingEmail,
  });

  final String id;
  final String organizationName;
  final String billingEmail;

  factory PayingPartyBillingSummary.fromJson(Map<String, dynamic> json) => PayingPartyBillingSummary(
        id: '${json['id']}',
        organizationName: json['organizationName'] as String? ??
            json['organization_name'] as String? ??
            '',
        billingEmail: json['billingEmail'] as String? ??
            json['billing_email'] as String? ??
            '',
      );
}

class BillingCounts {
  const BillingCounts({
    required this.subscriptions,
    required this.orders,
    required this.invoices,
  });

  final SubscriptionStatusCounts subscriptions;
  final OrderStatusCounts orders;
  final InvoiceStatusCounts invoices;

  factory BillingCounts.fromJson(Map<String, dynamic> json) => BillingCounts(
        subscriptions: SubscriptionStatusCounts.fromJson(
          (json['subscriptions'] as Map<String, dynamic>?) ?? const {},
        ),
        orders: OrderStatusCounts.fromJson(
          (json['orders'] as Map<String, dynamic>?) ?? const {},
        ),
        invoices: InvoiceStatusCounts.fromJson(
          (json['invoices'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

class SubscriptionStatusCounts {
  const SubscriptionStatusCounts({
    this.total = 0,
    this.active = 0,
    this.pastDue = 0,
    this.canceled = 0,
    this.paused = 0,
    this.vacant = 0,
  });

  final int total;
  final int active;
  final int pastDue;
  final int canceled;
  final int paused;
  final int vacant;

  factory SubscriptionStatusCounts.fromJson(Map<String, dynamic> json) =>
      SubscriptionStatusCounts(
        total: _asInt(json['total']),
        active: _asInt(json['active']),
        pastDue: _asInt(json['pastDue'] ?? json['past_due']),
        canceled: _asInt(json['canceled']),
        paused: _asInt(json['paused']),
        vacant: _asInt(json['vacant']),
      );
}

class OrderStatusCounts {
  const OrderStatusCounts({
    this.total = 0,
    this.paid = 0,
    this.pending = 0,
    this.failed = 0,
  });

  final int total;
  final int paid;
  final int pending;
  final int failed;

  factory OrderStatusCounts.fromJson(Map<String, dynamic> json) => OrderStatusCounts(
        total: _asInt(json['total']),
        paid: _asInt(json['paid']),
        pending: _asInt(json['pending']),
        failed: _asInt(json['failed']),
      );
}

class InvoiceStatusCounts {
  const InvoiceStatusCounts({
    this.total = 0,
    this.paid = 0,
    this.open = 0,
    this.overdue = 0,
    this.failed = 0,
  });

  final int total;
  final int paid;
  final int open;
  final int overdue;
  final int failed;

  factory InvoiceStatusCounts.fromJson(Map<String, dynamic> json) => InvoiceStatusCounts(
        total: _asInt(json['total']),
        paid: _asInt(json['paid']),
        open: _asInt(json['open']),
        overdue: _asInt(json['overdue']),
        failed: _asInt(json['failed']),
      );
}

class RecentInvoiceSummary {
  const RecentInvoiceSummary({
    required this.id,
    required this.invoiceNumber,
    required this.amount,
    required this.currency,
    required this.status,
    this.paidAt,
    this.createdAt,
  });

  final String id;
  final String invoiceNumber;
  final double amount;
  final String currency;
  final String status;
  final DateTime? paidAt;
  final DateTime? createdAt;

  factory RecentInvoiceSummary.fromJson(Map<String, dynamic> json) => RecentInvoiceSummary(
        id: '${json['id']}',
        invoiceNumber: json['invoiceNumber'] as String? ??
            json['invoice_number'] as String? ??
            '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? '',
        status: json['status'] as String? ?? '',
        paidAt: _parseDateTime(json['paidAt'] ?? json['paid_at']),
        createdAt: _parseDateTime(json['createdAt'] ?? json['created_at']),
      );
}

List<RecentInvoiceSummary> _parseRecentInvoices(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(RecentInvoiceSummary.fromJson)
      .toList();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  return null;
}
