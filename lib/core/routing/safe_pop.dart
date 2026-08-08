import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Back that works even when there is nothing to go back to.
///
/// `context.pop()` throws when the navigator stack is empty, and it can be
/// empty legitimately: opening a deep link straight into a session, or
/// arriving after a chain of `pushReplacement` calls — which the Console does
/// every time you switch shells from the sidebar. A back button that crashes
/// is worse than one that guesses, so this falls back to the surface the
/// screen belongs to.
extension SafePop on BuildContext {
  void popOr(String fallbackRouteName) {
    if (canPop()) {
      pop();
    } else {
      goNamed(fallbackRouteName);
    }
  }
}
