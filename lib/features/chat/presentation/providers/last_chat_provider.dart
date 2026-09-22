import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The most-recently-opened chat id.
///
/// Lets sibling surfaces return to the CURRENT chat **directly** instead of
/// round-tripping the bootstrap screen (`goNamed('chats')`), which re-fetches
/// the whole chat list, re-resolves a target, and flashes "Opening your
/// chat…". Set by [ChatDetailScreen] on open; null before any chat is opened
/// (then callers fall back to the bootstrap path).
final lastChatIdProvider = StateProvider<String?>((ref) => null);

/// Return to the CURRENT chat directly, falling back to the bootstrap screen
/// only when no chat has been opened yet.
///
/// Use for **return-to-chat** actions (the Ask toggle, closing Settings,
/// finishing Billing, leaving a shell session). Do NOT use for fresh entries
/// (login, consent) or error recovery where the current chat is the *bad* one
/// (a 403'd chat) — those must go through bootstrap so it resolves a different,
/// valid chat.
void goToCurrentChat(BuildContext context, WidgetRef ref) {
  final last = ref.read(lastChatIdProvider);
  if (last != null) {
    context.goNamed('chat-detail', pathParameters: {'id': last});
  } else {
    context.goNamed('chats');
  }
}
