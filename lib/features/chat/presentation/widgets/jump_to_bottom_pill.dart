import 'package:flutter/material.dart';

/// Small floating pill shown when the user has scrolled up while a
/// conversation (possibly still streaming) continues below. Tapping returns
/// to the newest message and re-attaches auto-follow.
class JumpToBottomPill extends StatelessWidget {
  const JumpToBottomPill({super.key, required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: visible ? 1 : 0.8,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Material(
            color: scheme.surfaceContainerHigh,
            shape: CircleBorder(
              side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
            ),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Semantics(
                  button: true,
                  label: 'Jump to newest message',
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 20,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
