import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/root_access.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/rootfs_installer.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/providers/distro_install_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/local_model_section.dart';

/// Console setup — where someone turns a terminal into a Linux environment.
///
/// This exists because installing a distro used to require an adb property.
/// That is fine for us and useless to a user, and "install what you need"
/// is the whole promise of the Console, so the setup has to be a screen.
///
/// It states the honest limits rather than discovering them for the user
/// mid-download: how big the thing actually is once unpacked, that PRoot is
/// not real root, and — on the Play build — that no distro can run at all.
class AgentEnvironmentScreen extends ConsumerWidget {
  const AgentEnvironmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final distros = ref.watch(distroListProvider);
    final active = ref.watch(activeDistroProvider);
    final backend = ref.watch(shellBackendProvider);
    // `direct` can execute a downloaded rootfs; `play` cannot, and no amount
    // of UI changes that. Saying so up front beats a download that ends in a
    // permission error.
    // Tri-state on purpose. Defaulting the unresolved case to `false` made
    // the screen assert "this build cannot run a distribution" for the moment
    // before the exec probe answered — alarming, wrong, and then it flipped.
    // Unknown gets a neutral line and disabled buttons instead of a verdict.
    final canRunAsync = ref.watch(canInstallDistrosProvider);
    final canRunDistro = canRunAsync.valueOrNull;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Agent environment')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Everything above the local-model section describes a shell this
          // device may not have. On a platform without one they are not
          // "unavailable", they are meaningless — so they are absent, and the
          // one section that still applies moves to the top.
          if (PlatformFlags.hasDeviceShell) ...[
            _CurrentEnvironment(label: backend?.label ?? 'Android shell'),
            const SizedBox(height: 14),
            const _RootSection(),
            const _ShellServiceSection(),
            const SizedBox(height: 22),
          ],
          // Above the distro list on purpose: pointing at a model server that
          // already exists is a thirty-second setup, while installing Linux is
          // a 400 MB download. The cheaper answer should be the one people see
          // first.
          const LocalModelSection(),
          const SizedBox(height: 22),
          if (PlatformFlags.hasDeviceShell) ...[
          Text('Linux distribution',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: cs.onSurfaceVariant,
              )),
          const SizedBox(height: 6),
          Text(
            switch (canRunDistro) {
              null => 'Checking what this build can run…',
              true => 'Install one to get a real package manager. Everything '
                  'runs on this device.',
              false => 'This build did not ship the PRoot runtime, so it '
                  'cannot start a distribution. Reinstall from '
                  'cyberneurova.ai if this looks wrong.',
            },
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final d in distros) ...[
            _DistroCard(
              state: d,
              isActive: active?.id == d.distro.id,
              // Also gated on a real checksum — see Distro.isVerified.
              enabled: (canRunDistro ?? false) && d.distro.isVerified,
              onInstall: () =>
                  ref.read(distroInstallProvider.notifier).install(d.distro),
              onCancel: () =>
                  ref.read(distroInstallProvider.notifier).cancel(d.distro.id),
              onRemove: () => _confirmRemove(context, ref, d.distro),
              onUse: () => _switchTo(context, ref, d.distro),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          _PackagesSection(active: active),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, Distro d) async {
    // Deleting a rootfs throws away everything installed into it. That is not
    // recoverable and not obvious from a bin icon, so it gets a confirmation
    // that says what is actually lost.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${d.name}?'),
        content: const Text(
          'Everything installed inside it goes too — packages, files and any '
          'work saved in the distribution. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(distroInstallProvider.notifier).remove(d);
    }
  }
}

class _CurrentEnvironment extends StatelessWidget {
  const _CurrentEnvironment({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Console is running',
                    style:
                        TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(label,
                    style: AppTheme.mono(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistroCard extends StatelessWidget {
  const _DistroCard({
    required this.state,
    required this.isActive,
    required this.enabled,
    required this.onInstall,
    required this.onCancel,
    required this.onRemove,
    this.onUse,
  });

  final DistroState state;
  final bool isActive;
  final bool enabled;
  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  /// Switch the Console to this distro. Null when it is already in use.
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = state.distro;
    final p = state.progress;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? cs.primary.withValues(alpha: 0.6)
                : cs.outline.withValues(alpha: 0.35),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${d.name} ${d.version}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        _Pill(text: 'in use', color: cs.primary),
                      ],
                    ],
                  ),
                ),
                _action(context, cs),
              ],
            ),
            const SizedBox(height: 6),
            Text(d.description,
                style: TextStyle(
                    fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sd_storage_outlined,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                // Installed size, not just download size — the number that
                // actually matters on a phone, and the one download UIs
                // usually hide.
                Text(d.sizeLabel,
                    style:
                        TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                const SizedBox(width: 12),
                Icon(Icons.inventory_2_outlined,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(d.packageManager,
                    style: AppTheme.mono(
                        fontSize: 11.5, color: cs.onSurfaceVariant)),
              ],
            ),
            if (!d.isVerified) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.hourglass_empty_rounded,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Not available yet — awaiting a verified checksum '
                        'from the distribution.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (d.notes != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(d.notes!,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            ],
            if (p != null && !p.isTerminal) ...[
              const SizedBox(height: 12),
              _Progress(progress: p),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 10),
              Text(
                state.error!,
                style: TextStyle(fontSize: 11.5, color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context, ColorScheme cs) {
    if (state.isBusy) {
      return TextButton(
        onPressed: onCancel,
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        child: const Text('Cancel'),
      );
    }
    if (state.installed) {
      // Installed but not the one in use: offer to switch. Without this the
      // second distro you install is dead weight — the Console silently keeps
      // booting whichever came first in the catalogue.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isActive && onUse != null)
            TextButton(
              onPressed: onUse,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: const Text('Use'),
            ),
          IconButton(
            tooltip: 'Remove',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon:
                Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
            onPressed: onRemove,
          ),
        ],
      );
    }
    return FilledButton(
      onPressed: enabled ? onInstall : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size(76, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: const Text('Install'),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});
  final InstallProgress progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = progress.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          // Indeterminate for verify/extract/configure: those stages have no
          // honest percentage, and a bar that pretends otherwise is worse
          // than one that admits it is working.
          child: LinearProgressIndicator(
            value: f,
            minHeight: 4,
            backgroundColor: cs.outline.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _label(progress),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
            if (f != null)
              Text('${(f * 100).round()}%',
                  style: AppTheme.mono(
                      fontSize: 11.5, color: cs.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  static String _label(InstallProgress p) => switch (p.stage) {
        InstallStage.downloading => 'Downloading',
        InstallStage.verifying => 'Verifying checksum',
        InstallStage.extracting => 'Extracting',
        InstallStage.configuring => 'Configuring',
        InstallStage.seeding => 'Installing Python',
        InstallStage.done => 'Ready',
        InstallStage.failed => p.message ?? 'Failed',
      };
}

/// How to install packages once a distro is in place.
///
/// Deliberately instructions rather than buttons. A curated grid of one-tap
/// installs would have to guess what someone wants and would rot the moment
/// upstream renames a package; the package manager already does this job
/// well, and the useful thing is telling people the exact command for the
/// distro they actually installed.
class _PackagesSection extends StatelessWidget {
  const _PackagesSection({required this.active});
  final Distro? active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pm = active?.packageManager;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Packages',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: cs.onSurfaceVariant,
            )),
        const SizedBox(height: 6),
        if (active == null)
          Text(
            'Install a distribution above, then packages become available in '
            'the Console.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          )
        else ...[
          Text(
            'Run these in the Console, or just ask the agent for what you '
            'need.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _Cmd('$pm update', 'Refresh the package index'),
          _Cmd(
            pm == 'apk' ? 'apk add tmux' : 'apt install -y tmux',
            'Terminal multiplexer',
          ),
          _Cmd(
            pm == 'apk' ? 'apk add nmap' : 'apt install -y nmap',
            'Network scanner (connect scans only — see note above)',
          ),
          _Cmd(
            pm == 'apk' ? 'apk add git python3' : 'apt install -y git python3',
            'Git and Python',
          ),
        ],
      ],
    );
  }
}

class _Cmd extends StatelessWidget {
  const _Cmd(this.command, this.why);
  final String command;
  final String why;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(9),
            ),
            child: SelectableText(
              command,
              style: AppTheme.mono(fontSize: 12.5, color: cs.onSurface),
            ),
          ),
          const SizedBox(height: 3),
          Text(why,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Root, if the device has it.
///
/// Shown only when a `su` binary was found — on the overwhelming majority of
/// phones this section simply does not exist, and an "enable root" control
/// that can never work would be noise at best and an invitation at worst. We
/// detect; we never suggest rooting.
/// Makes [distro] the one the Console runs in.
///
/// Only affects shells opened after this point. A pane already running has a
/// live PTY inside the old rootfs, and silently killing someone's session —
/// possibly mid-command — to apply a settings change is not a trade worth
/// making. Say so instead.
Future<void> _switchTo(
  BuildContext context,
  WidgetRef ref,
  Distro distro,
) async {
  await ref.read(preferredDistroProvider.notifier).select(distro.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('New Console sessions will use ${distro.name}. '
          'Sessions already open keep the one they started in.'),
      duration: const Duration(seconds: 4),
    ),
  );
}

class _RootSection extends ConsumerWidget {
  const _RootSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final found = ref.watch(rootAccessProvider).valueOrNull;
    final grant = ref.watch(rootGrantProvider);

    // Nothing found, or still looking: render nothing at all.
    if (found == null || found.status == RootStatus.unavailable) {
      return const SizedBox.shrink();
    }

    final granted = grant.isUsable;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: granted
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                granted ? Icons.shield_rounded : Icons.shield_outlined,
                size: 18,
                color: granted ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                granted ? 'Root enabled' : 'Root available',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            granted
                ? 'Tools that need real root work here — SYN scans, packet '
                    'capture and monitor mode. The agent is told it has them.'
                : 'This device has su. Granting root lets tools that need it '
                    'actually run: SYN scans, packet capture, monitor mode. '
                    'Without it those fail no matter which distro you install.',
            style: TextStyle(
                fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
          if (grant.status == RootStatus.denied && grant.detail != null) ...[
            const SizedBox(height: 8),
            Text(
              grant.detail!,
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: granted
                ? OutlinedButton(
                    onPressed: () =>
                        ref.read(rootGrantProvider.notifier).revoke(),
                    child: const Text('Stop using root'),
                  )
                : FilledButton(
                    // Only here does anything run su, so the permission
                    // prompt appears because the user asked for it.
                    onPressed: () =>
                        ref.read(rootGrantProvider.notifier).request(),
                    child: const Text('Grant root'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The ADB shell service (Shizuku), if it is reachable.
///
/// Unlike root, this section shows even when unavailable — because unlike
/// root, it is something the user can actually go and get, on any phone, with
/// no computer. Hiding it would hide the single biggest capability upgrade
/// most people can make.
class _ShellServiceSection extends ConsumerWidget {
  const _ShellServiceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final status = ref.watch(shellServiceStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();

    final uid = ref.watch(shellServiceUidProvider).valueOrNull ?? -1;
    final on = status == ShellServiceStatus.granted;
    final alreadyPaired =
        ref.watch(adbPairedProvider).valueOrNull ?? false;

    // A rooted device already has everything this section offers, and more.
    // Showing it a "set up shell access" flow would be asking the user to do
    // work to obtain strictly less than they have — su is a superset of uid
    // 2000, and only su carries kernel capabilities.
    if (ref.watch(rootGrantProvider).isUsable) return const SizedBox.shrink();

    // Each state gets its own words. "Install Shizuku" and "you already have
    // it, just allow us" are different instructions, and one message covering
    // both sends people round in circles.
    final (String title, String body, String? action) = switch (status) {
      ShellServiceStatus.granted => (
          uid == 0 ? 'Shell access (root service)' : 'Shell access connected',
          'The privileged channel is connected. No agent tool routes through '
              'it yet, so app installs still show Android’s own confirmation.',
          null,
        ),
      ShellServiceStatus.present => (
          'Shell access available',
          'Shizuku is running. Allowing it connects the privileged channel. '
              'Nothing uses it yet — this is groundwork.',
          'Allow',
        ),
      ShellServiceStatus.denied => (
          'Shell access refused',
          'You declined earlier. Nothing is broken — the agent simply asks '
              'for confirmation on anything it installs.',
          'Ask again',
        ),
      ShellServiceStatus.unsupported => (
          'Shizuku is too old',
          'This version predates the API we use. Updating Shizuku will fix '
              'it.',
          null,
        ),
      // Two different states behind one card. Shizuku is absent either way,
      // but a device that has ALREADY been paired needs Connect, not Set up —
      // and calling that "not set up" contradicted the screen the button
      // opened, which greeted the user with "Paired with this device".
      ShellServiceStatus.unavailable => alreadyPaired
          ? (
              'Shell access paired, not connected',
              'Wireless debugging switches itself off when you reboot. Turn '
                  'it back on in Developer options and reconnect — the '
                  'pairing is remembered, so there is no code to enter.',
              'Connect',
            )
          : (
              'Shell access not set up',
              'Optional groundwork. Your phone pairs with its own wireless '
                  'debugging — no computer, no root, nothing to install. '
                  'Nothing uses it yet: installs still go through Android’s '
                  'confirmation, and there is no uninstall or package-list '
                  'tool.',
              'Set up',
            ),
    };

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: on
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on ? Icons.terminal_rounded : Icons.terminal_outlined,
                size: 18,
                color: on ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (on)
                Text(
                  'uid $uid',
                  style:
                      AppTheme.mono(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
                fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () async {
                  // No Shizuku: our own pairing flow is the way in.
                  if (status == ShellServiceStatus.unavailable) {
                    context.pushNamed('adb-pairing');
                    return;
                  }
                  await ShellService.requestPermission();
                  // Ask the platform again rather than assuming the answer —
                  // the user may have dismissed the dialog without choosing.
                  ref.invalidate(shellServiceStatusProvider);
                  ref.invalidate(shellServiceUidProvider);
                },
                child: Text(action),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
