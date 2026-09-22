// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Sign up';

  @override
  String get signOut => 'Sign out';

  @override
  String get signInToContinue => 'Sign in to continue';

  @override
  String get createAccount => 'Create account';

  @override
  String get joinCyberNeurovaFree => 'Join CyberNeurova for free';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get dontHaveAccount => 'Don\'t have an account? Sign up';

  @override
  String get alreadyHaveAccount => 'Already have an account? Sign in';

  @override
  String get orDivider => 'OR';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get enterValidEmail => 'Enter a valid email';

  @override
  String get passwordTooShort => 'Password too short';

  @override
  String get passwordMin8 => 'At least 8 characters';

  @override
  String get enterYourPassword => 'Enter your password';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get resetPasswordHint =>
      'Enter your account email and we\'ll send you a link to reset your password.';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get checkYourEmail => 'Check your email';

  @override
  String resetSentBody(String email) {
    return 'If an account exists for $email, a reset link is on its way. Check your spam folder if you don\'t see it.';
  }

  @override
  String get verifyEmailTitle => 'Check your email';

  @override
  String verifyEmailBody(String email) {
    return 'We sent a verification link to $email. Tap the link to activate your account, then sign in.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Chats';

  @override
  String get images => 'Images';

  @override
  String get discover => 'Discover';

  @override
  String get profile => 'Profile';

  @override
  String get noChatsYet => 'No conversations yet';

  @override
  String get startChattingHint => 'Start chatting with CyberNeurova AI';

  @override
  String get newConversation => 'New conversation';

  @override
  String get messageInputHint => 'Message CyberNeurova...';

  @override
  String get howCanIHelp => 'How can I help you today?';

  @override
  String get search => 'Search';

  @override
  String get searchChatsHint => 'Search chats…';

  @override
  String get typeToSearchChats => 'Type to search your chats';

  @override
  String noChatsMatch(String query) {
    return 'No chats match \"$query\"';
  }

  @override
  String get rename => 'Rename';

  @override
  String get deleteChat => 'Delete chat';

  @override
  String get deleteChatQuestion => 'Delete chat?';

  @override
  String get cannotBeUndone => 'This cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get retry => 'Retry';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get waitForResponseToFinish => 'Wait for the response to finish.';

  @override
  String get noImagesYet => 'No images yet';

  @override
  String get tapGenerateHint => 'Tap Generate to create your first image';

  @override
  String get generate => 'Generate';

  @override
  String get generateImage => 'Generate Image';

  @override
  String get describeImage => 'Describe the image you want...';

  @override
  String get yourImageWillAppear => 'Your image will appear here';

  @override
  String get starting => 'Starting...';

  @override
  String generatingPercent(int percent) {
    return 'Generating $percent%';
  }

  @override
  String get generateAnother => 'Generate another';

  @override
  String get generationFailed => 'Generation failed';

  @override
  String get trending => 'Trending';

  @override
  String get recent => 'Recent';

  @override
  String get nothingToDiscover => 'Nothing to discover yet';

  @override
  String get freePlan => 'Free Plan';

  @override
  String get premiumPlan => 'Premium Plan';

  @override
  String get proPlan => 'Pro Plan';

  @override
  String get proMaxPlan => 'Pro Max Plan';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get upgradeHint => 'Upgrade for more tokens & models';

  @override
  String get tokenUsage => 'Token Usage';

  @override
  String get used => 'used';

  @override
  String get limit => 'limit';

  @override
  String get settings => 'Settings';

  @override
  String get notifications => 'Notifications';

  @override
  String get changePassword => 'Change password';

  @override
  String get language => 'Language';

  @override
  String get account => 'Account';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get activeSessions => 'Active sessions';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountConfirm =>
      'Permanently delete your account? This cannot be undone.';

  @override
  String get deleteAccountPasswordOptional =>
      'Leave blank if you signed in with Google or Apple.';

  @override
  String get signOutQuestion => 'Sign out?';

  @override
  String get signOutBody => 'You will need to log in again.';

  @override
  String get voiceInput => 'Voice input';

  @override
  String get voiceInputHint => 'Hold to record, release to send.';

  @override
  String get voiceTranscribing => 'Transcribing…';

  @override
  String get voicePermissionDenied => 'Microphone permission denied.';

  @override
  String get attach => 'Attach';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get fromLibrary => 'From library';

  @override
  String get uploadingFile => 'Uploading…';

  @override
  String get shareChat => 'Share chat';

  @override
  String get visibility => 'Visibility';

  @override
  String get visibilityPrivate => 'Private';

  @override
  String get visibilityShared => 'Shared with specific people';

  @override
  String get visibilityPublic => 'Public link';

  @override
  String get shareWithEmail => 'Share with someone (email)';

  @override
  String get addPerson => 'Add';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork => 'No internet connection.';

  @override
  String get errorSessionExpired => 'Session expired. Please sign in again.';

  @override
  String errorRateLimited(int seconds) {
    return 'Too many requests. Try again in ${seconds}s.';
  }

  @override
  String get errorQuotaExceeded => 'Token quota exceeded.';

  @override
  String get errorServer => 'Server error. Try again later.';

  @override
  String get couldNotOpenBrowser => 'Could not open browser.';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get newChat => 'New chat';

  @override
  String get media => 'Media';

  @override
  String get research => 'Research';

  @override
  String get recents => 'Recents';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => 'Your chats will appear here';

  @override
  String get billing => 'Billing';

  @override
  String get usageLabel => 'Usage';

  @override
  String get customPrompts => 'Custom prompts';

  @override
  String get memory => 'Memory';

  @override
  String get capabilities => 'Capabilities';

  @override
  String get designLab => 'Design Lab';

  @override
  String get skills => 'Skills';

  @override
  String get tools => 'Tools';

  @override
  String get premiumRequired => 'Premium feature — upgrade to enable';

  @override
  String get memoryEmptyTitle => 'No memories yet';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova will start saving important context from your chats here.';

  @override
  String get memoryAtCapacity =>
      'Memory at capacity — oldest entries will be replaced.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Memory almost full ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Last extracted $when';
  }

  @override
  String get categoryPreferences => 'Preferences';

  @override
  String get categoryFacts => 'Facts';

  @override
  String get categoryProjects => 'Projects';

  @override
  String get categoryPatterns => 'Patterns';

  @override
  String get categoryContext => 'Context';

  @override
  String get researchAll => 'All';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'Exploit';

  @override
  String get researchBugBounty => 'Bug bounty';

  @override
  String get researchMalware => 'Malware';

  @override
  String get researchPentest => 'Pentest';

  @override
  String get newResearch => 'New research';

  @override
  String get noResearchYet => 'No research sessions yet';

  @override
  String get researchEmptyHint =>
      'Start a new research session to investigate CVEs, exploits, or threats.';

  @override
  String get sources => 'Sources';

  @override
  String get close => 'Close';

  @override
  String get doneLabel => 'Done';

  @override
  String get projectsTitle => 'Projects';

  @override
  String get freePlan2 => 'Free plan';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'System';

  @override
  String get noConversations => 'No conversations yet';

  @override
  String get promptBrainstorm => 'Brainstorm ideas';

  @override
  String get promptExplain => 'Explain a concept';

  @override
  String get promptCode => 'Help me write code';
}
