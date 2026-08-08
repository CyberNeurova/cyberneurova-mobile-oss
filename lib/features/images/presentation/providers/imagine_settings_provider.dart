import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UI-only Imagine settings (Grok pass).
///
/// IMPORTANT: the backend's generate endpoint accepts ONLY `prompt` today
/// (see ImageRepository.generateImage — body is `{'prompt': prompt}`), so
/// NOTHING here is sent with the request. These values drive the Imagine
/// surface's quick chip + settings sheet UI and get wired through the
/// moment the API grows the matching fields. Do not fake request params.

class AspectRatioOption {
  const AspectRatioOption(this.label, this.width, this.height);
  final String label;

  /// Relative proportions for the visual selector rectangle.
  final double width;
  final double height;
}

const imagineAspectRatios = [
  AspectRatioOption('1:1', 1, 1),
  AspectRatioOption('2:3', 2, 3),
  AspectRatioOption('3:2', 3, 2),
  AspectRatioOption('9:16', 9, 16),
  AspectRatioOption('16:9', 16, 9),
];

/// Selected aspect-ratio label. Deliberately NOT autoDispose so the
/// selection survives leaving and re-entering the Imagine surface
/// within a session (matches imageGenerationProvider's lifetime).
final imagineAspectRatioProvider = StateProvider<String>((_) => '1:1');
