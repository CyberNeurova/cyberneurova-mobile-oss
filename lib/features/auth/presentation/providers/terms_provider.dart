import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/features/auth/data/models/terms_model.dart';
import 'package:cyberneurova_mobile/features/auth/data/repositories/auth_repository.dart';

/// Fetches the current ToS version + canonical URLs. Used by the register
/// screen to render the legal-acceptance checkbox and to send `tosVersion`
/// back in the create-account request.
///
/// autoDispose so we re-fetch every time the register screen mounts —
/// catches the case where a long-lived install has gone stale relative to
/// the server's CURRENT_TOS_VERSION (the backend API spec).
final termsProvider = FutureProvider.autoDispose<TermsInfo>((ref) async {
  return ref.read(authRepositoryProvider).fetchCurrentTerms();
});
