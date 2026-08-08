class AppConstants {
  AppConstants._();

  static const String appName = 'CyberNeurova';
  static const String appVersion = '1.0.0';

  // Secure storage keys
  static const String kAccessToken = 'access_token';
  static const String kRefreshToken = 'refresh_token';
  static const String kUserId = 'user_id';

  // SharedPreferences keys
  static const String kOnboardingDone = 'onboarding_done';
  static const String kThemeMode = 'theme_mode';
  static const String kSelectedModel = 'selected_model';

  // Pagination
  static const int defaultPageLimit = 20;
  static const int messagesPageLimit = 50;

  // Streaming
  static const String streamEventStart = 'start';
  static const String streamEventToken = 'token';
  static const String streamEventUsage = 'usage';
  static const String streamEventDone = 'done';
  static const String streamEventError = 'error';

  // Subscription tiers
  static const String tierFree = 'free';
  static const String tierPremium = 'premium';
  static const String tierPro = 'pro';
  static const String tierProMax = 'pro_max';

  // Chat sections
  static const String sectionChat = 'chat';
  static const String sectionCode = 'code';
  static const String sectionResearch = 'research';
  /// Shell workspace — terminal + agent sharing one execution context
  /// (`docs/shell/00-OVERVIEW.md`). The **only** session type where device
  /// tools (scans, LAN probes) are available. Not yet a built surface; the
  /// constant exists so the gate has something to key on and so sessions are
  /// already tagged when the workspace lands.
  static const String sectionShell = 'shell';

  // Public URLs (also referenced in App Store Connect privacy fields)
  static const String privacyPolicyUrl = 'https://cyberneurova.ai/privacy';
  static const String termsUrl = 'https://cyberneurova.ai/terms';
}
