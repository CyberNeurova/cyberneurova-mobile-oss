import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/core/agent/local/local_llm.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/local_llm_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Point the app at a model server that is not ours.
///
/// ## Why this is worth a section
///
/// Every practical local runtime — llama.cpp's server, Ollama, LM Studio,
/// vLLM — already speaks the OpenAI API. The app already speaks it too. So
/// "use a local model" is a base URL, not a second inference stack: one
/// running inside the user's own distro on this phone, or one on their laptop
/// across the room.
///
/// Only the laptop half exists on a platform with no Linux session, and the
/// copy below says so — telling someone to start a server inside a distro
/// they cannot have is an instruction to a dead end.
///
/// Both work with no internet at all, which is the point for someone on a
/// metered connection or none — and it is only possible because this app runs
/// the work on the user's own device and network rather than in a datacentre.
class LocalModelSection extends ConsumerStatefulWidget {
  const LocalModelSection({super.key});

  @override
  ConsumerState<LocalModelSection> createState() => _LocalModelSectionState();
}

class _LocalModelSectionState extends ConsumerState<LocalModelSection> {
  final _url = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save(String raw) async {
    setState(() => _saving = true);
    final saved = await ref.read(localLlmBaseUrlProvider.notifier).set(raw);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = saved == null;
    });
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("That doesn't look like an address"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = ref.watch(localLlmBaseUrlProvider);
    final status = ref.watch(localLlmStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Local model',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          // "on this phone" is only true where we can give the user a Linux
          // session to start one in. Offering it on a platform that cannot is
          // an instruction they can follow to a dead end.
          PlatformFlags.hasDeviceShell
              ? 'Run a model on this phone or on your own machine. Anything '
                  'that speaks the OpenAI API works — llama.cpp, Ollama, LM '
                  'Studio. No internet needed once it is running.'
              : 'Point this at a model running on your own machine. Anything '
                  'that speaks the OpenAI API works — llama.cpp, Ollama, LM '
                  'Studio. Both devices need to be on the same network.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),

        if (base != null && !_editing)
          _Chosen(
            baseUrl: base,
            status: status,
            onChange: () {
              _url.text = base;
              setState(() => _editing = true);
            },
            onForget: () => ref.read(localLlmBaseUrlProvider.notifier).clear(),
            onRecheck: () => ref.invalidate(localLlmStatusProvider),
          )
        else ...[
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_saving,
            onSubmitted: _save,
            style: AppTheme.mono(fontSize: 13, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              hintText: '192.168.1.5:11434',
              hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              suffixIcon: IconButton(
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                onPressed: _saving ? null : () => _save(_url.text),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _Discovery(),
        ],
      ],
    );
  }
}

/// The endpoint in use, and whether it is actually answering.
class _Chosen extends ConsumerWidget {
  const _Chosen({
    required this.baseUrl,
    required this.status,
    required this.onChange,
    required this.onForget,
    required this.onRecheck,
  });

  final String baseUrl;
  final AsyncValue<LocalEndpoint?> status;
  final VoidCallback onChange;
  final VoidCallback onForget;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final active = ref.watch(localLlmModelProvider);
    final endpoint = status.valueOrNull;
    final checking = status.isLoading;
    final usable = endpoint?.isUsable ?? false;
    final emptyServer = endpoint?.isEmpty ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A dot, not a word: the state changes often and a sentence that
              // rewrites itself every few seconds is noise.
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checking
                      ? cs.onSurfaceVariant
                      // Amber for up-but-empty: it is not broken and it is
                      // not ready, and calling it either would be wrong.
                      : usable
                          ? cs.primary
                          : (emptyServer ? cs.tertiary : cs.error),
                ),
              ),
              Expanded(
                child: Text(
                  baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(fontSize: 12.5, color: cs.onSurface),
                ),
              ),
              IconButton(
                tooltip: 'Check again',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: onRecheck,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (checking)
            Text('Checking…',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
          else if (emptyServer)
            Text(
              '${endpoint!.flavour ?? 'The server'} is running but has no '
              'models loaded. Pull or load one, then check again.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
            )
          else if (!usable)
            Text(
              // Says what to check rather than just that it failed. The three
              // causes are always the same and the user can act on all three.
              'Not answering. Check the server is running, that the phone is '
              'on the same network, and that it is listening on all '
              'interfaces rather than only localhost.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
            )
          else ...[
            Text(
              '${endpoint!.models.length} model'
              '${endpoint.models.length == 1 ? '' : 's'}'
              '${endpoint.flavour == null ? '' : ' · ${endpoint.flavour}'}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in endpoint.models.take(8))
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      // Tapping the model in use turns routing OFF again, so
                      // there is no separate switch to hunt for and no state
                      // where a model looks chosen but is not being used.
                      final notifier =
                          ref.read(localLlmModelProvider.notifier);
                      if (active == m.id) {
                        notifier.stop();
                      } else {
                        notifier.use(m.id);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: active == m.id
                            ? cs.primary
                            : cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (active == m.id) ...[
                            Icon(Icons.check_rounded,
                                size: 12, color: cs.onPrimary),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            m.id,
                            style: AppTheme.mono(
                              fontSize: 11,
                              color: active == m.id
                                  ? cs.onPrimary
                                  : cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          if (active != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              // Said plainly: routing away from our servers changes what the
              // app can do, and the user should never have to infer that from
              // a highlighted chip.
              child: Text(
                'Messages go to this model instead of CyberNeurova. No tools '
                'or web search on this path.',
                style: TextStyle(
                    fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant),
              ),
            ),
          Row(
            children: [
              TextButton(onPressed: onChange, child: const Text('Change')),
              TextButton(onPressed: onForget, child: const Text('Forget')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sweeps the usual ports on this phone so nobody has to type anything.
class _Discovery extends ConsumerWidget {
  const _Discovery();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final found = ref.watch(localLlmDiscoveryProvider);

    return found.when(
      loading: () => Row(
        children: [
          const SizedBox(
              width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(
              PlatformFlags.hasDeviceShell
                  ? 'Looking on this phone…'
                  : 'Looking on your network…',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
      // A failed sweep is not worth a red box: it means "nothing here", which
      // is the ordinary answer on a phone with no server running.
      error: (_, __) => const SizedBox.shrink(),
      data: (endpoints) {
        if (endpoints.isEmpty) {
          return Text(
            // Without a Linux session there is nothing to start one INSIDE,
            // so only the second half of this advice survives.
            PlatformFlags.hasDeviceShell
                ? 'Nothing running on this phone yet. Start one inside your '
                    'Linux session, or type the address of a machine on your '
                    'network.'
                : 'Type the address of a machine on your network — for '
                    'example http://192.168.1.10:11434 for Ollama.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in endpoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    ref.read(localLlmBaseUrlProvider.notifier).set(e.baseUrl);
                  },
                  child: Row(
                    children: [
                      Icon(Icons.memory_rounded, size: 15, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.isEmpty
                              ? '${e.flavour ?? 'Server'} · no models yet'
                              : '${e.flavour ?? 'Server'} · '
                                  '${e.models.length} model'
                                  '${e.models.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                        ),
                      ),
                      Text(
                        Uri.parse(e.baseUrl).port.toString(),
                        style: AppTheme.mono(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
