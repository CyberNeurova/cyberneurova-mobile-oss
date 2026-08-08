import 'package:freezed_annotation/freezed_annotation.dart';

part 'terms_model.freezed.dart';
part 'terms_model.g.dart';

/// Current Terms of Service version + canonical URLs. Returned by
/// `GET /api/mobile/v1/legal/terms`. Used by the register screen to
/// (a) render the "I accept the Terms…" checkbox with the correct
/// links and (b) send the version back as `tosVersion` so the server
/// can detect drift and re-prompt.
@freezed
class TermsInfo with _$TermsInfo {
  const factory TermsInfo({
    @Default('1.0') String version,
    @Default('https://cyberneurova.ai/privacy') String termsUrl,
    @Default('https://cyberneurova.ai/privacy') String privacyUrl,
  }) = _TermsInfo;

  factory TermsInfo.fromJson(Map<String, dynamic> json) =>
      _$TermsInfoFromJson(json);
}
