/// Labels for a billing row.
///
/// Split out of the screen so the filter, the chip count and the badge cannot
/// drift apart — they did: the list showed a "completed" $30 payment while the
/// Paid chip read "(0)".
library;

/// The plan a payment was for.
///
/// This was a switch with `_ => 'Free'`, so any tier the client did not know
/// became "Free" — and the owner's own history showed **"Free · $250.00"** and
/// two "Free · $15.00" rows. A paid invoice labelled Free is worse than an
/// unlabelled one: it reads as though the charge was a mistake.
///
/// There is a standing note in this project that tier maps keep omitting
/// `starter` and silently degrade paying users to free, and that the `?? free`
/// idiom is the tell. This was that idiom.
///
/// Unknown tiers are now humanised rather than renamed. The client does not
/// need to know every plan the billing system will ever have; it needs to not
/// lie about the ones it does not.
String tierLabel(String tier) {
  final t = tier.trim().toLowerCase();
  return switch (t) {
    '' => 'Plan',
    'free' => 'Free',
    'starter' => 'Starter',
    'premium' => 'Premium',
    'pro' => 'Pro',
    'pro_max' || 'promax' => 'Pro Max',
    _ => _humanise(t),
  };
}

/// `some_new_tier` → `Some New Tier`.
String _humanise(String raw) => raw
    .split(RegExp(r'[_\s-]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Whether a payment status means the money went through.
///
/// The server sends `completed` as well as `paid`. The screen only knew
/// `paid`, so a completed payment fell through to the default branch, was
/// labelled with the raw lowercase status, and was counted in neither the Paid
/// bucket nor the Failed one — "All (6)" beside "Paid (0)" with a completed
/// $30 row on screen.
bool isPaidStatus(String status) {
  final s = status.trim().toLowerCase();
  return s == 'paid' || s == 'completed' || s == 'succeeded' || s == 'success';
}

/// Whether a status belongs in the Failed bucket, which also collects the
/// endings that are not failures but are not money either.
bool isFailedStatus(String status) {
  final s = status.trim().toLowerCase();
  return s == 'failed' || s == 'cancelled' || s == 'canceled' || s == 'expired';
}

/// Whether a payment is still in flight.
bool isPendingStatus(String status) {
  final s = status.trim().toLowerCase();
  return s == 'pending' || s == 'processing';
}

/// A status a person can read, for anything the buckets above do not name.
String statusLabel(String status) {
  final s = status.trim();
  if (s.isEmpty) return 'Unknown';
  if (isPaidStatus(s)) return 'Paid';
  if (isPendingStatus(s)) return 'Pending';
  return switch (s.toLowerCase()) {
    'failed' => 'Failed',
    'cancelled' || 'canceled' => 'Cancelled',
    'expired' => 'Expired',
    _ => _humanise(s.toLowerCase()),
  };
}
