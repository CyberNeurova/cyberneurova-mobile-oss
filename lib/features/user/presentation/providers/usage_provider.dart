import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/features/user/data/models/usage_model.dart';
import 'package:cyberneurova_mobile/features/user/data/repositories/user_repository.dart';

/// Detailed usage breakdown — session / weekly / weeklyPremium / extras.
/// autoDispose so the screen always fetches fresh on mount (token counters
/// change frequently).
final usageDetailProvider = FutureProvider.autoDispose<UsageDetail>((ref) {
  return ref.read(userRepositoryProvider).getUsage();
});
