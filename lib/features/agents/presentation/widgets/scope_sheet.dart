import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Declares what the agent is authorized to touch in this session.
///
/// Scope is a **control surface, not advice**. `docs/shell/00-OVERVIEW.md`
/// AD-6: any tool that emits packets at a target has that target checked
/// against this list, and out-of-scope targets are refused by the executor
/// rather than discouraged in a prompt. The device re-checks independently of
/// the server, so a replayed frame cannot widen it.
///
/// It is also a feature, not just a guard: professional testers need a record
/// of what they were authorized to touch, which is why the note field exists.
Future<void> showScopeSheet(BuildContext context, String chatId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
    ),
    builder: (_) => _ScopeSheet(chatId: chatId),
  );
}

class _ScopeSheet extends ConsumerStatefulWidget {
  const _ScopeSheet({required this.chatId});
  final String chatId;

  @override
  ConsumerState<_ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends ConsumerState<_ScopeSheet> {
  late bool _includeLocal;
  late List<String> _cidrs;
  late List<String> _hosts;
  late final TextEditingController _entry;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    final scope = ref.read(sessionScopeProvider(widget.chatId));
    _includeLocal = scope.includeLocalSubnet;
    _cidrs = [...scope.cidrs];
    _hosts = [...scope.hostPatterns];
    _entry = TextEditingController();
    _note = TextEditingController(text: scope.note ?? '');
  }

  @override
  void dispose() {
    _entry.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Accepts either a CIDR or a hostname pattern and files it correctly, so
  /// the user doesn't have to know which list they're adding to.
  void _add() {
    final raw = _entry.text.trim();
    if (raw.isEmpty) return;

    if (raw.contains('/')) {
      if (!_looksLikeCidr(raw)) {
        setState(() => _error = '"$raw" is not a valid CIDR.');
        return;
      }
      setState(() {
        if (!_cidrs.contains(raw)) _cidrs.add(raw);
        _entry.clear();
        _error = null;
      });
      return;
    }

    if (!_looksLikeHost(raw)) {
      setState(() =>
          _error = 'Enter a CIDR (10.0.0.0/24) or a hostname (*.example.com).');
      return;
    }
    setState(() {
      if (!_hosts.contains(raw)) _hosts.add(raw);
      _entry.clear();
      _error = null;
    });
  }

  void _save() {
    HapticFeedback.mediumImpact();
    ref.read(sessionScopeProvider(widget.chatId).notifier).declare(
          AuthorizedScope(
            cidrs: _cidrs,
            hostPatterns: _hosts,
            includeLocalSubnet: _includeLocal,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subnets = ref.watch(localSubnetsProvider).valueOrNull ?? const [];
    final isEmpty = !_includeLocal && _cidrs.isEmpty && _hosts.isEmpty;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                'Authorized scope',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The agent may only send traffic at what you list here. '
                'Anything else is refused on this device, not just discouraged.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 18),

              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _includeLocal,
                onChanged: (v) => setState(() => _includeLocal = v),
                title: Text(
                  'This network',
                  style: TextStyle(fontSize: 15, color: cs.onSurface),
                ),
                subtitle: Text(
                  subnets.isEmpty
                      ? "Couldn't determine the current subnet"
                      // Resolved live, so it follows the user onto a new
                      // network and stops authorising the old one.
                      : '${subnets.join(', ')} — re-checked on every call',
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),

              if (_cidrs.isNotEmpty || _hosts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in _cidrs)
                      _ScopeChip(
                        label: c,
                        onRemove: () => setState(() => _cidrs.remove(c)),
                      ),
                    for (final h in _hosts)
                      _ScopeChip(
                        label: h,
                        onRemove: () => setState(() => _hosts.remove(h)),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _entry,
                      onSubmitted: (_) => _add(),
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '10.0.0.0/24  or  *.example.com',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded, size: 20),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: TextStyle(fontSize: 12.5, color: cs.error)),
              ],

              const SizedBox(height: 14),
              TextField(
                controller: _note,
                style: TextStyle(fontSize: 14, color: cs.onSurface),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Engagement reference (optional)',
                  hintText: 'Client name, ticket, authorization ref',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),

              const SizedBox(height: 16),
              if (isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'With nothing listed, only this device is '
                          'targetable. That is a safe default, not an error.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save scope'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _looksLikeCidr(String s) {
    final parts = s.split('/');
    if (parts.length != 2) return false;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return false;
    final octets = parts[0].split('.');
    if (octets.length != 4) return false;
    return octets.every((o) {
      final n = int.tryParse(o);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static bool _looksLikeHost(String s) =>
      RegExp(r'^(\*\.)?[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$',
              caseSensitive: false)
          .hasMatch(s);
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontFamily: 'monospace',
              color: cs.primary,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.close_rounded, size: 14, color: cs.primary),
            onPressed: () {
              HapticFeedback.selectionClick();
              onRemove();
            },
          ),
        ],
      ),
    );
  }
}
