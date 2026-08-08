import 'package:cyberneurova_mobile/features/payment/presentation/screens/billing_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/billing_models.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/providers/billing_provider.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

class BillingHistoryScreen extends ConsumerStatefulWidget {
  const BillingHistoryScreen({super.key});

  @override
  ConsumerState<BillingHistoryScreen> createState() =>
      _BillingHistoryScreenState();
}

class _BillingHistoryScreenState extends ConsumerState<BillingHistoryScreen> {
  // all | paid | pending | failed (failed bucket also covers cancelled/expired)
  String _filter = 'all';

  bool _matches(HistoricalPayment p) {
    if (_filter == 'all') return true;
    if (_filter == 'failed') return isFailedStatus(p.status);
    if (_filter == 'paid') return isPaidStatus(p.status);
    if (_filter == 'pending') return isPendingStatus(p.status);
    return p.status.toLowerCase() == _filter;
  }

  @override
  Widget build(BuildContext context) {
    final asyncHistory = ref.watch(paymentHistoryProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Billing history'),
      ),
      body: asyncHistory.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, __) => const CnShimmer(
              width: double.infinity, height: 64, radius: 14),
        ),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.refresh(paymentHistoryProvider.future),
        ),
        data: (resp) {
          if (resp.payments.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No payments yet',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            );
          }
          // Newest first, then apply the active category filter.
          final sorted = [...resp.payments]..sort((a, b) {
              final da = a.paidAt ?? a.createdAt;
              final db = b.paidAt ?? b.createdAt;
              if (da == null && db == null) return 0;
              if (da == null) return 1;
              if (db == null) return -1;
              return db.compareTo(da);
            });
          final filtered = sorted.where(_matches).toList();

          int countFor(String f) {
            if (f == 'all') return sorted.length;
            return sorted.where((p) {
              if (f == 'failed') return isFailedStatus(p.status);
              if (f == 'paid') return isPaidStatus(p.status);
              if (f == 'pending') return isPendingStatus(p.status);
              return p.status.toLowerCase() == f;
            }).length;
          }

          return Column(
            children: [
              // Category filter row
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final f in const [
                      ('all', 'All'),
                      ('paid', 'Paid'),
                      ('pending', 'Pending'),
                      ('failed', 'Failed'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: '${f.$2} (${countFor(f.$1)})',
                          selected: _filter == f.$1,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _filter = f.$1);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No ${_filter == 'all' ? '' : '$_filter '}payments',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _PaymentRow(payment: filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? cs.primary : cs.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

/// (label, color, icon) for a payment status.
({String label, Color color, IconData icon}) _statusStyle(
    BuildContext context, String status) {
  final cs = Theme.of(context).colorScheme;
  if (isPaidStatus(status)) {
    return (label: 'Paid', color: cs.primary, icon: Icons.check_rounded);
  }
  switch (status.toLowerCase()) {
    case 'pending':
      return (
        label: 'Pending',
        color: const Color(0xFFFFB347),
        icon: Icons.hourglass_top_rounded
      );
    case 'failed':
      return (label: 'Failed', color: cs.error, icon: Icons.close_rounded);
    case 'cancelled':
      return (
        label: 'Cancelled',
        color: cs.onSurfaceVariant,
        icon: Icons.block_rounded
      );
    case 'expired':
      return (
        label: 'Expired',
        color: cs.onSurfaceVariant,
        icon: Icons.schedule_rounded
      );
    default:
      return (
        // Was the raw server string, so "completed" appeared lowercase beside
        // properly-cased labels.
        label: statusLabel(status),
        color: cs.onSurfaceVariant,
        icon: Icons.receipt_long_rounded
      );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});
  final HistoricalPayment payment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = _statusStyle(context, payment.status);
    final date = payment.paidAt ?? payment.createdAt;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: st.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(st.icon, size: 20, color: st.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _tierLabel(payment.tier),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: st.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        st.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: st.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  date != null
                      ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                      : '—',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${payment.amount.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _tierLabel(String t) => tierLabel(t);
}
