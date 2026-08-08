import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';

/// Bottom sheet for changing visibility, sharing by email, copying public link.
Future<void> showShareChatSheet(
  BuildContext context, {
  required String chatId,
  String initialVisibility = 'private',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // sheetCtx is the BUILDER's own context — its MediaQuery rebuilds when
    // the keyboard appears, lifting the sheet above the keyboard. Earlier
    // we used the OUTER `context` here, which captured viewInsets at
    // sheet-open time and never updated — keyboard covered the email
    // field, looking like "typing does nothing."
    builder: (sheetCtx) => AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
      ),
      child: _ShareChatSheet(
        chatId: chatId,
        initialVisibility: initialVisibility,
      ),
    ),
  );
}

class _ShareChatSheet extends ConsumerStatefulWidget {
  const _ShareChatSheet({
    required this.chatId,
    required this.initialVisibility,
  });
  final String chatId;
  final String initialVisibility;

  @override
  ConsumerState<_ShareChatSheet> createState() => _ShareChatSheetState();
}

class _ShareChatSheetState extends ConsumerState<_ShareChatSheet> {
  late String _visibility = widget.initialVisibility;
  final _email = TextEditingController();
  final _emailFocus = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _changeVisibility(String v) async {
    if (v == _visibility) return;
    HapticFeedback.selectionClick();
    setState(() {
      _visibility = v;
      _saving = true;
    });
    // If the user just chose "shared", auto-focus the email field once the
    // visibility update settles. The email input is conditionally rendered
    // — without auto-focus the user can miss it entirely.
    if (v == 'shared') {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _emailFocus.requestFocus();
      });
    }
    try {
      await ref
          .read(chatRepositoryProvider)
          .updateVisibility(widget.chatId, v);
    } catch (e) {
      // Revert on error
      setState(() => _visibility = widget.initialVisibility);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessageFor(context, e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addShare() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .shareWithEmail(widget.chatId, email);
      _email.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shared with $email'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessageFor(context, e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyLink() async {
    HapticFeedback.lightImpact();
    final url = _publicUrl();
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppL10n.of(context).linkCopied),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _publicUrl() {
    final base = ApiConstants.baseUrl
        .replaceAll(RegExp(r'/api/mobile/v\d+/*$'), '');
    return '$base/chat/${widget.chatId}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.shareChat,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            Text(
              l10n.visibility,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _VisibilityOption(
              icon: Icons.lock_outline_rounded,
              title: l10n.visibilityPrivate,
              value: 'private',
              groupValue: _visibility,
              onChanged: _changeVisibility,
            ),
            _VisibilityOption(
              icon: Icons.people_alt_outlined,
              title: l10n.visibilityShared,
              value: 'shared',
              groupValue: _visibility,
              onChanged: _changeVisibility,
            ),
            _VisibilityOption(
              icon: Icons.public_rounded,
              title: l10n.visibilityPublic,
              value: 'public',
              groupValue: _visibility,
              onChanged: _changeVisibility,
            ),

            if (_visibility == 'shared') ...[
              const SizedBox(height: 16),
              Text(
                l10n.shareWithEmail,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _email,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      onSubmitted: (_) => _addShare(),
                      decoration: const InputDecoration(
                        hintText: 'name@example.com',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _addShare,
                    child: Text(l10n.addPerson),
                  ),
                ],
              ),
            ],

            if (_visibility == 'public') ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.link_rounded),
                label: Text(l10n.copyLink),
                onPressed: _copyLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.icon,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = value == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: cs.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
