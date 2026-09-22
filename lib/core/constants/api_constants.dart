// ignore_for_file: constant_identifier_names
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://cyberneurova.ai/api/mobile/v1',
  );

  /// Scheme + host of the chat-app web origin, derived from [baseUrl].
  /// Used to resolve image URLs the API returns as host-relative paths
  /// (e.g. `/api/images/<uuid>/view`) — those are NOT relative to
  /// [baseUrl]'s `/api/mobile/v1` prefix, they're relative to the host.
  /// Without this prefix, [CachedNetworkImage] would 404 every image.
  static String get webOrigin {
    final u = Uri.parse(baseUrl);
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port';
  }

  /// Resolve any image URL the API returned. Pass-through if absolute,
  /// prepended with [webOrigin] if it starts with `/`.
  static String resolveImageUrl(String urlFromApi) {
    if (urlFromApi.startsWith('http://') ||
        urlFromApi.startsWith('https://')) {
      return urlFromApi;
    }
    if (urlFromApi.startsWith('/')) return '$webOrigin$urlFromApi';
    return '$webOrigin/$urlFromApi';
  }

  /// True only for our own secure asset origin (https + same host:port as
  /// [webOrigin]). Used to decide whether the Bearer token may be attached to
  /// an image request — the token must NEVER be sent to a third-party or
  /// cleartext host.
  static bool isOwnOrigin(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https') return false;
    final origin = Uri.parse(webOrigin);
    return u.host == origin.host && u.port == origin.port;
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 90);
  static const Duration sendTimeout = Duration(seconds: 30);

  // Files
  static const String FILES_UPLOAD = '/files/upload';

  // Analytics
  static const String ANALYTICS_EVENTS = '/analytics/events';

  // Legal
  static const String LEGAL_TERMS = '/legal/terms';

  // Auth
  static const String AUTH_REGISTER = '/auth/register';
  static const String AUTH_LOGIN = '/auth/login';
  static const String AUTH_GOOGLE = '/auth/google';
  static const String AUTH_APPLE = '/auth/apple';
  static const String AUTH_REFRESH = '/auth/refresh';
  static const String AUTH_LOGOUT = '/auth/logout';
  static const String AUTH_ME = '/auth/me';
  static const String AUTH_FORGOT_PASSWORD = '/auth/forgot-password';
  static const String AUTH_RESET_PASSWORD = '/auth/reset-password';

  // Sessions
  static const String USER_SESSIONS = '/user/sessions';

  // Chat
  static const String CHAT = '/chat';
  static String chatById(String id) => '/chat/$id';
  static String chatMessages(String id) => '/chat/$id/messages';
  static String chatComplete(String id) => '/chat/$id/complete';

  // ── run protocol (chat-team inbox/029, live on prod 2026-08-04) ──────────
  // The agent surfaces send here rather than to /complete. The difference is
  // not the URL: /complete carries the deviceContext STRING and no tools, so
  // a model told about tools in prose emits the call template as text. This
  // path attaches the 8 real device tool schemas, which is what makes a tool
  // call a tool call.
  static const String AGENT_RUN = '/agent/run';
  static const String AGENT_CONTROL = '/agent/control';
  static const String AGENT_DEVICE_RESULT = '/agent/device_result';
  static String chatResume(String id) => '/chat/$id/complete/resume';
  static String chatShare(String id) => '/chat/$id/share';

  // ── Bot section / Agent Contacts (inbox/042, 043) ────────────────────────
  // The mobile proxy validates our JWT and forwards to an ISOLATED bot-section
  // instance (scoped cn_botsection PG role), so these are safe to build+persist
  // against directly — there is no separate dev host. Contract:
  // cyberneurova_core/docs/BOT_SECTION_API.md. All paths are under baseUrl.
  static const String BOT_AGENTS = '/bot/agents';
  static String botAgentById(String id) => '/bot/agents/$id';
  static String botAgentMemory(String id) => '/bot/agents/$id/memory';
  static const String BOT_ROOMS = '/bot/rooms';
  static String botRoomById(String id) => '/bot/rooms/$id';
  static String botRoomMessages(String id) => '/bot/rooms/$id/messages';
  static String botRoomParticipants(String id) => '/bot/rooms/$id/participants';
  static String botRoomNextSpeaker(String id) => '/bot/rooms/$id/next-speaker';
  static String botRoomRuns(String id) => '/bot/rooms/$id/runs';
  static String botRoomCommands(String id) => '/bot/rooms/$id/commands';
  static String botRoomFiles(String id) => '/bot/rooms/$id/files';
  static const String BOT_STREAM = '/bot/stream'; // multiplexed SSE (all rooms)
  static const String BOT_PRESENCE = '/bot/presence';

  // ── Remote control (mobile = controller; relay) ──────────────────────────
  // Chat spec `collaborationdir/mobile/chat/2026-08-29-0840`. SCAFFOLD: the
  // relay isn't live yet, and the exact base/auth is pending confirmation on
  // wiring (proxy maps these to the engine `/v1/remote/*` shape).
  static const String REMOTE_DEVICES = '/remote/devices';
  static const String REMOTE_SESSION = '/remote/session';

  // User
  static const String USER_TOKENS = '/user/tokens';
  static const String USER_SUBSCRIPTION = '/user/subscription';
  static const String USER_SETTINGS = '/user/settings'; // preferences only (theme, notifications)
  static const String USER_PROFILE = '/user/profile';  // name + image — shipped 2026-06-01
  static const String USER_DELETE = '/user/delete';
  static const String USER_PROMPTS = '/user/prompts';
  static String userPromptById(String id) => '/user/prompts/$id';

  // Payment
  static const String PAYMENT_PLANS = '/payment/plans';
  static const String PAYMENT_CREATE = '/payment/create';
  static const String PAYMENT_STATUS = '/payment/status';
  static const String PAYMENT_HISTORY = '/payment/history';

  // IAP (Apple / Google store purchases — inbox/026)
  static const String IAP_VERIFY = '/iap/verify';
  static const String IAP_STATUS = '/iap/status';

  // Models
  static const String MODELS = '/models';

  // Images
  static const String IMAGES = '/images';
  static const String IMAGES_GENERATE = '/images/generate';

  // Video
  // Video endpoints removed from mobile UI 2026-06-05 (server-side
  // feature still exists at /video; bring back if the feature returns
  // to mobile).

  // Memory
  static const String MEMORY = '/memory';
  static String memoryById(String id) => '/memory/$id';

  // Skills
  static const String SKILLS = '/skills';
  static String skillToggle(String id) => '/skills/$id';

  // Search
  // /search exists server-side but mobile doesn't call it directly. The AI
  // agent handles web search itself during chat completion (chat-team's
  // WebSearchTool is always enabled). See inbox/005.
  // static const String SEARCH = '/search';

  // Shared
  static const String SHARED = '/shared';

  // Projects
  static const String PROJECTS = '/projects';
  static String projectById(String id) => '/projects/$id';
  static String projectChats(String id) => '/projects/$id/chats';

  // Voice ("speak" + "listen" — both backed by Box A media services)
  static const String VOICE_AUTH = '/voice/auth';
  static const String VOICE_TRANSCRIBE = '/voice/transcribe'; // POST multipart: file
  static const String TTS = '/tts'; // POST JSON: text, speaker, max_audio_length_ms
}
