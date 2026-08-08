import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SourceItem {
  const SourceItem({
    required this.title,
    required this.url,
    this.faviconUrl,
    this.snippet,
  });
  final String title;
  final String url;
  final String? faviconUrl;
  final String? snippet;

  /// Derives a favicon URL from the source URL if not provided.
  String get effectiveFavicon {
    if (faviconUrl != null && faviconUrl!.isNotEmpty) return faviconUrl!;
    try {
      final host = Uri.parse(url).host;
      return 'https://www.google.com/s2/favicons?domain=$host&sz=64';
    } catch (_) {
      return '';
    }
  }

  String get host {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}

/// Show citations / web sources used by the assistant in a bottom sheet.
Future<void> showSourcesSheet(
  BuildContext context, {
  required List<SourceItem> sources,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SourcesSheet(sources: sources),
  );
}

class _SourcesSheet extends StatelessWidget {
  const _SourcesSheet({required this.sources});
  final List<SourceItem> sources;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  const Text(
                    'Sources',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, i) => _SourceRow(
                  index: i + 1,
                  source: sources[i],
                  isLast: i == sources.length - 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.index,
    required this.source,
    required this.isLast,
  });

  final int index;
  final SourceItem source;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        HapticFeedback.lightImpact();
        // Sahachiel: only ever open real web sources over http(s). This list is
        // built from the assistant's web-search results (server-supplied), so a
        // compromised or malicious response could carry javascript: / intent: /
        // file: / data: URIs that launchUrl would otherwise hand straight to the
        // OS. Restricting the scheme here is safe - a citation is always a web URL.
        final uri = Uri.tryParse(source.url);
        if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
          return;
        }
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Numbered timeline dot + favicon
            Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainerHigh,
                    border: Border.all(color: cs.outline),
                  ),
                  alignment: Alignment.center,
                  child: source.faviconUrl != null ||
                          source.effectiveFavicon.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: source.effectiveFavicon,
                            width: 14,
                            height: 14,
                            errorWidget: (_, __, ___) => Text(
                              '$index',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          '$index',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                if (!isLast)
                  Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.only(top: 4),
                    color: cs.outline,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    source.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (source.snippet != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      source.snippet!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.open_in_new_rounded,
                size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Compact "Sources" pill shown under an assistant message — tap to open.
class SourcesChip extends StatelessWidget {
  const SourcesChip({super.key, required this.sources});
  final List<SourceItem> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showSourcesSheet(context, sources: sources),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sources',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            // Stacked favicons preview (up to 3)
            SizedBox(
              width: 16.0 * (sources.length.clamp(1, 3)) - 4,
              height: 16,
              child: Stack(
                children: List.generate(
                  sources.length.clamp(0, 3),
                  (i) => Positioned(
                    left: i * 12.0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.surface,
                        border: Border.all(
                            color: cs.surface, width: 1.5),
                      ),
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: sources[i].effectiveFavicon,
                          errorWidget: (_, __, ___) => Container(
                            color: cs.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
