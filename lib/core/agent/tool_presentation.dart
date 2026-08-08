import 'package:flutter/material.dart';

/// How to display a tool call the client may know nothing about.
///
/// The engine (`cyberneurova_core`) ships 46 tools and will grow more, and
/// MCP servers can add tools at runtime that no client build has ever heard
/// of. So the rule here is: **every tool renders usefully, known or not.**
///
/// Known tools get a hand-tuned icon, verb and argument summary. Unknown
/// tools fall back to a derived label and a generic key/value view of their
/// arguments. Adding a tool to the backend never requires an app release —
/// it only means the card is a little less pretty until one ships.
class ToolPresentation {
  const ToolPresentation({
    required this.icon,
    required this.label,
    required this.runningVerb,
    this.primaryArgKeys = const [],
    this.accent,
  });

  final IconData icon;

  /// Human-readable tool name ("Web search", not "WebSearchTool").
  final String label;

  /// Present-progressive phrase shown while running ("Searching the web").
  final String runningVerb;

  /// Argument keys worth showing in the collapsed summary, in priority
  /// order. Empty means "show whatever looks most useful".
  final List<String> primaryArgKeys;

  final Color? accent;

  /// Resolves presentation for [tool], falling back to a derived one.
  static ToolPresentation of(String tool) {
    final normalized = _normalize(tool);
    return _known[normalized] ?? _derive(tool);
  }

  /// Strips the conventional `Tool` suffix and lowercases, so `WebSearchTool`,
  /// `web_search` and `WebSearch` all resolve to the same entry.
  static String _normalize(String tool) {
    var t = tool.trim();
    if (t.toLowerCase().endsWith('tool') && t.length > 4) {
      t = t.substring(0, t.length - 4);
    }
    return t.replaceAll(RegExp(r'[_\-\s]'), '').toLowerCase();
  }

  /// Best-effort presentation for a tool we have no entry for.
  ///
  /// `net_capture` → "Net capture" / "Running net capture". Not elegant, but
  /// it never shows a raw identifier and never shows nothing.
  static ToolPresentation _derive(String tool) {
    var name = tool.trim();
    if (name.toLowerCase().endsWith('tool') && name.length > 4) {
      name = name.substring(0, name.length - 4);
    }
    // camelCase / PascalCase → spaced words.
    name = name.replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])(?=[A-Z])'),
      (_) => ' ',
    );
    name = name.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (name.isEmpty) name = 'Tool';
    final label = name[0].toUpperCase() + name.substring(1).toLowerCase();
    return ToolPresentation(
      icon: Icons.bolt_rounded,
      label: label,
      runningVerb: 'Running ${label.toLowerCase()}',
    );
  }

  static const _known = <String, ToolPresentation>{
    'websearch': ToolPresentation(
      icon: Icons.travel_explore_rounded,
      label: 'Web search',
      runningVerb: 'Searching the web',
      primaryArgKeys: ['query', 'q'],
    ),
    'webfetch': ToolPresentation(
      icon: Icons.link_rounded,
      label: 'Fetch page',
      runningVerb: 'Fetching page',
      primaryArgKeys: ['url'],
    ),
    'bash': ToolPresentation(
      icon: Icons.terminal_rounded,
      label: 'Shell',
      runningVerb: 'Running command',
      primaryArgKeys: ['command'],
    ),
    'shellexec': ToolPresentation(
      icon: Icons.terminal_rounded,
      label: 'Shell',
      runningVerb: 'Running command',
      primaryArgKeys: ['command'],
    ),
    'fileread': ToolPresentation(
      icon: Icons.description_outlined,
      label: 'Read file',
      runningVerb: 'Reading',
      primaryArgKeys: ['file_path', 'path'],
    ),
    'filewrite': ToolPresentation(
      icon: Icons.edit_note_rounded,
      label: 'Write file',
      runningVerb: 'Writing',
      primaryArgKeys: ['file_path', 'path'],
    ),
    'fileedit': ToolPresentation(
      icon: Icons.edit_rounded,
      label: 'Edit file',
      runningVerb: 'Editing',
      primaryArgKeys: ['file_path', 'path'],
    ),
    'glob': ToolPresentation(
      icon: Icons.folder_open_rounded,
      label: 'Find files',
      runningVerb: 'Finding files',
      primaryArgKeys: ['pattern'],
    ),
    'grep': ToolPresentation(
      icon: Icons.search_rounded,
      label: 'Search code',
      runningVerb: 'Searching',
      primaryArgKeys: ['pattern'],
    ),
    'agent': ToolPresentation(
      icon: Icons.hub_outlined,
      label: 'Subagent',
      runningVerb: 'Delegating',
      primaryArgKeys: ['description', 'prompt'],
    ),
    'todowrite': ToolPresentation(
      icon: Icons.checklist_rounded,
      label: 'Plan',
      runningVerb: 'Updating the plan',
    ),
    'cvelookup': ToolPresentation(
      icon: Icons.security_rounded,
      label: 'CVE lookup',
      runningVerb: 'Looking up CVE',
      primaryArgKeys: ['cve_id', 'id', 'query'],
    ),
    'netdiscover': ToolPresentation(
      icon: Icons.lan_outlined,
      label: 'Discover hosts',
      runningVerb: 'Discovering hosts',
      primaryArgKeys: ['target'],
    ),
    'netscan': ToolPresentation(
      icon: Icons.radar_rounded,
      label: 'Port scan',
      runningVerb: 'Scanning',
      primaryArgKeys: ['target', 'ports'],
    ),
    'netcapture': ToolPresentation(
      icon: Icons.wifi_tethering_rounded,
      label: 'Capture traffic',
      runningVerb: 'Capturing traffic',
      primaryArgKeys: ['filter', 'duration_s'],
    ),
    'netanalyze': ToolPresentation(
      icon: Icons.analytics_outlined,
      label: 'Analyze capture',
      runningVerb: 'Analyzing capture',
      primaryArgKeys: ['path'],
    ),
    'httpprobe': ToolPresentation(
      icon: Icons.http_rounded,
      label: 'HTTP probe',
      runningVerb: 'Probing',
      primaryArgKeys: ['url', 'method'],
    ),
    'dnsquery': ToolPresentation(
      icon: Icons.dns_outlined,
      label: 'DNS lookup',
      runningVerb: 'Resolving',
      primaryArgKeys: ['name', 'domain'],
    ),
    'reportwrite': ToolPresentation(
      icon: Icons.assignment_outlined,
      label: 'Write finding',
      runningVerb: 'Recording finding',
      primaryArgKeys: ['title'],
    ),
  };
}

/// Picks the most informative one-line summary of a tool's arguments.
///
/// Tries [ToolPresentation.primaryArgKeys] first, then a set of conventional
/// names, then falls back to the first scalar value present. Returns null
/// when there is genuinely nothing worth showing — the caller should then
/// render nothing rather than an empty row.
String? summarizeToolArgs(
  Map<String, dynamic> input,
  ToolPresentation presentation,
) {
  if (input.isEmpty) return null;

  for (final key in presentation.primaryArgKeys) {
    final v = input[key];
    if (v != null) {
      final s = _scalar(v);
      if (s != null && s.isNotEmpty) return s;
    }
  }

  // Conventional names, in rough order of how much they tell a reader.
  const conventional = [
    'query', 'command', 'url', 'target', 'path', 'file_path',
    'pattern', 'prompt', 'description', 'name', 'title', 'q',
  ];
  for (final key in conventional) {
    final v = input[key];
    if (v != null) {
      final s = _scalar(v);
      if (s != null && s.isNotEmpty) return s;
    }
  }

  // Anything scalar at all, so an unknown tool still says something.
  for (final entry in input.entries) {
    final s = _scalar(entry.value);
    if (s != null && s.isNotEmpty) return '${entry.key}: $s';
  }
  return null;
}

String? _scalar(Object? v) {
  if (v is String) return v.trim().isEmpty ? null : v.trim();
  if (v is num || v is bool) return '$v';
  if (v is List && v.isNotEmpty) {
    final parts = [
      for (final e in v.take(3))
        if (_scalar(e) case final s?) s,
    ];
    if (parts.isEmpty) return null;
    return v.length > 3
        ? '${parts.join(', ')} +${v.length - 3}'
        : parts.join(', ');
  }
  return null;
}

/// Flattens tool arguments into displayable rows for the expanded view and
/// the approval card. Nested objects are JSON-ish rather than dropped, so
/// nothing is invisible to the user approving it.
List<({String key, String value})> toolArgRows(Map<String, dynamic> input) {
  final rows = <({String key, String value})>[];
  for (final entry in input.entries) {
    final scalar = _scalar(entry.value);
    rows.add((
      key: entry.key,
      value: scalar ?? _compact(entry.value),
    ));
  }
  return rows;
}

String _compact(Object? v) {
  if (v == null) return 'null';
  if (v is Map) {
    return '{${v.keys.take(4).join(', ')}${v.length > 4 ? ', …' : ''}}';
  }
  if (v is List) return '[${v.length} items]';
  return v.toString();
}
