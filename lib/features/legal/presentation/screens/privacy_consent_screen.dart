import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// First-launch data-handling disclosure. Required by Apple guideline
/// 5.1.1(i) + 5.1.2(i): before the app sends any user content to our
/// backend for AI processing, we have to explicitly say what data leaves
/// the device, who receives it, and get explicit consent.
///
/// The reviewer feedback that triggered this (build 30, 2026-07-02):
///
/// > The app appears to share the user's personal data with a third-party
/// > AI service but the app does not clearly explain what data is sent,
/// > identify who the data is sent to, and ask the user's permission
/// > before sharing the data.
///
/// Apple was mistaken about "third-party" (models are self-hosted), but
/// the disclosure requirement stands regardless. This screen is shown on
/// first launch and never again once the user taps "I Agree."
class PrivacyConsentScreen extends ConsumerStatefulWidget {
  const PrivacyConsentScreen({super.key});

  static const String prefsKey = 'privacy_consent_v1';

  /// True once the user has agreed on this install.
  static Future<bool> alreadyAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  @override
  ConsumerState<PrivacyConsentScreen> createState() =>
      _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends ConsumerState<PrivacyConsentScreen> {
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrivacyConsentScreen.prefsKey, true);
    if (!mounted) return;
    context.goNamed('chats');
  }

  Future<void> _openPolicy() async {
    final uri = Uri.parse('https://cyberneurova.ai/privacy');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.shield_outlined, size: 40, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                'How your data is handled',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Before you start chatting, please review how CyberNeurova handles your data.',
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              const Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Item(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'What data is sent',
                        body:
                            'Your messages, any files or images you attach, and the model you selected are sent to CyberNeurova\'s AI servers so the model can generate a reply.',
                      ),
                      _Item(
                        icon: Icons.dns_rounded,
                        title: 'Who receives it',
                        body:
                            'Only CyberNeurova (cyberneurova.ai). Our AI models are self-hosted on infrastructure we operate. We do not use any third-party AI service (no OpenAI, Anthropic, Google, or similar). Your data is not shared with any third party for AI processing.',
                      ),
                      _Item(
                        icon: Icons.storage_rounded,
                        title: 'How it\'s used',
                        body:
                            'Signed-in users: your chat history is saved to your account so you can pick up where you left off. Unsigned users see a chat shell only; no messages are sent until you sign in. We never train on or sell your data.',
                      ),
                      _Item(
                        icon: Icons.lock_outline_rounded,
                        title: 'Your control',
                        body:
                            'You can delete individual chats or your entire account from Settings at any time. Full details in our privacy policy.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _openPolicy,
                child: const Text('Read the full privacy policy'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _accepting ? null : _accept,
                child: _accepting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : const Text('I Agree'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
