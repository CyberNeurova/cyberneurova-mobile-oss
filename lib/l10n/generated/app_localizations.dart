import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_th.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('ru'),
    Locale('th'),
    Locale('tr'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'CyberNeurova'**
  String get appName;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get signInToContinue;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @joinCyberNeurovaFree.
  ///
  /// In en, this message translates to:
  /// **'Join CyberNeurova for free'**
  String get joinCyberNeurovaFree;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @nameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get nameOptional;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get dontHaveAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get alreadyHaveAccount;

  /// No description provided for @orDivider.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get orDivider;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enterValidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password too short'**
  String get passwordTooShort;

  /// No description provided for @passwordMin8.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordMin8;

  /// No description provided for @enterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterYourPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPassword;

  /// No description provided for @resetPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your account email and we\'ll send you a link to reset your password.'**
  String get resetPasswordHint;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get sendResetLink;

  /// No description provided for @backToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get backToSignIn;

  /// No description provided for @checkYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get checkYourEmail;

  /// No description provided for @resetSentBody.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, a reset link is on its way. Check your spam folder if you don\'t see it.'**
  String resetSentBody(String email);

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailBody.
  ///
  /// In en, this message translates to:
  /// **'We sent a verification link to {email}. Tap the link to activate your account, then sign in.'**
  String verifyEmailBody(String email);

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noChatsYet;

  /// No description provided for @startChattingHint.
  ///
  /// In en, this message translates to:
  /// **'Start chatting with CyberNeurova AI'**
  String get startChattingHint;

  /// No description provided for @newConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get newConversation;

  /// No description provided for @messageInputHint.
  ///
  /// In en, this message translates to:
  /// **'Message CyberNeurova...'**
  String get messageInputHint;

  /// No description provided for @howCanIHelp.
  ///
  /// In en, this message translates to:
  /// **'How can I help you today?'**
  String get howCanIHelp;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchChatsHint.
  ///
  /// In en, this message translates to:
  /// **'Search chats…'**
  String get searchChatsHint;

  /// No description provided for @typeToSearchChats.
  ///
  /// In en, this message translates to:
  /// **'Type to search your chats'**
  String get typeToSearchChats;

  /// No description provided for @noChatsMatch.
  ///
  /// In en, this message translates to:
  /// **'No chats match \"{query}\"'**
  String noChatsMatch(String query);

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @deleteChatQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete chat?'**
  String get deleteChatQuestion;

  /// No description provided for @cannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get cannotBeUndone;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @waitForResponseToFinish.
  ///
  /// In en, this message translates to:
  /// **'Wait for the response to finish.'**
  String get waitForResponseToFinish;

  /// No description provided for @noImagesYet.
  ///
  /// In en, this message translates to:
  /// **'No images yet'**
  String get noImagesYet;

  /// No description provided for @tapGenerateHint.
  ///
  /// In en, this message translates to:
  /// **'Tap Generate to create your first image'**
  String get tapGenerateHint;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @generateImage.
  ///
  /// In en, this message translates to:
  /// **'Generate Image'**
  String get generateImage;

  /// No description provided for @describeImage.
  ///
  /// In en, this message translates to:
  /// **'Describe the image you want...'**
  String get describeImage;

  /// No description provided for @yourImageWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Your image will appear here'**
  String get yourImageWillAppear;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting...'**
  String get starting;

  /// No description provided for @generatingPercent.
  ///
  /// In en, this message translates to:
  /// **'Generating {percent}%'**
  String generatingPercent(int percent);

  /// No description provided for @generateAnother.
  ///
  /// In en, this message translates to:
  /// **'Generate another'**
  String get generateAnother;

  /// No description provided for @generationFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get generationFailed;

  /// No description provided for @trending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get trending;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @nothingToDiscover.
  ///
  /// In en, this message translates to:
  /// **'Nothing to discover yet'**
  String get nothingToDiscover;

  /// No description provided for @freePlan.
  ///
  /// In en, this message translates to:
  /// **'Free Plan'**
  String get freePlan;

  /// No description provided for @premiumPlan.
  ///
  /// In en, this message translates to:
  /// **'Premium Plan'**
  String get premiumPlan;

  /// No description provided for @proPlan.
  ///
  /// In en, this message translates to:
  /// **'Pro Plan'**
  String get proPlan;

  /// No description provided for @proMaxPlan.
  ///
  /// In en, this message translates to:
  /// **'Pro Max Plan'**
  String get proMaxPlan;

  /// No description provided for @upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get upgrade;

  /// No description provided for @upgradeHint.
  ///
  /// In en, this message translates to:
  /// **'Upgrade for more tokens & models'**
  String get upgradeHint;

  /// No description provided for @tokenUsage.
  ///
  /// In en, this message translates to:
  /// **'Token Usage'**
  String get tokenUsage;

  /// No description provided for @used.
  ///
  /// In en, this message translates to:
  /// **'used'**
  String get used;

  /// No description provided for @limit.
  ///
  /// In en, this message translates to:
  /// **'limit'**
  String get limit;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @activeSessions.
  ///
  /// In en, this message translates to:
  /// **'Active sessions'**
  String get activeSessions;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account? This cannot be undone.'**
  String get deleteAccountConfirm;

  /// No description provided for @deleteAccountPasswordOptional.
  ///
  /// In en, this message translates to:
  /// **'Leave blank if you signed in with Google or Apple.'**
  String get deleteAccountPasswordOptional;

  /// No description provided for @signOutQuestion.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutQuestion;

  /// No description provided for @signOutBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to log in again.'**
  String get signOutBody;

  /// No description provided for @voiceInput.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get voiceInput;

  /// No description provided for @voiceInputHint.
  ///
  /// In en, this message translates to:
  /// **'Hold to record, release to send.'**
  String get voiceInputHint;

  /// No description provided for @voiceTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get voiceTranscribing;

  /// No description provided for @voicePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied.'**
  String get voicePermissionDenied;

  /// No description provided for @attach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attach;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @fromLibrary.
  ///
  /// In en, this message translates to:
  /// **'From library'**
  String get fromLibrary;

  /// No description provided for @uploadingFile.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploadingFile;

  /// No description provided for @shareChat.
  ///
  /// In en, this message translates to:
  /// **'Share chat'**
  String get shareChat;

  /// No description provided for @visibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get visibility;

  /// No description provided for @visibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get visibilityPrivate;

  /// No description provided for @visibilityShared.
  ///
  /// In en, this message translates to:
  /// **'Shared with specific people'**
  String get visibilityShared;

  /// No description provided for @visibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'Public link'**
  String get visibilityPublic;

  /// No description provided for @shareWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Share with someone (email)'**
  String get shareWithEmail;

  /// No description provided for @addPerson.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addPerson;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get errorNetwork;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Try again in {seconds}s.'**
  String errorRateLimited(int seconds);

  /// No description provided for @errorQuotaExceeded.
  ///
  /// In en, this message translates to:
  /// **'Token quota exceeded.'**
  String get errorQuotaExceeded;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'Server error. Try again later.'**
  String get errorServer;

  /// No description provided for @couldNotOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Could not open browser.'**
  String get couldNotOpenBrowser;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @research.
  ///
  /// In en, this message translates to:
  /// **'Research'**
  String get research;

  /// No description provided for @recents.
  ///
  /// In en, this message translates to:
  /// **'Recents'**
  String get recents;

  /// No description provided for @chatsWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Your chats will appear here'**
  String get chatsWillAppearHere;

  /// No description provided for @billing.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billing;

  /// No description provided for @usageLabel.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usageLabel;

  /// No description provided for @customPrompts.
  ///
  /// In en, this message translates to:
  /// **'Custom prompts'**
  String get customPrompts;

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @capabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get capabilities;

  /// No description provided for @designLab.
  ///
  /// In en, this message translates to:
  /// **'Design Lab'**
  String get designLab;

  /// No description provided for @skills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skills;

  /// No description provided for @tools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tools;

  /// No description provided for @premiumRequired.
  ///
  /// In en, this message translates to:
  /// **'Premium feature — upgrade to enable'**
  String get premiumRequired;

  /// No description provided for @memoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No memories yet'**
  String get memoryEmptyTitle;

  /// No description provided for @memoryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'CyberNeurova will start saving important context from your chats here.'**
  String get memoryEmptyHint;

  /// No description provided for @memoryAtCapacity.
  ///
  /// In en, this message translates to:
  /// **'Memory at capacity — oldest entries will be replaced.'**
  String get memoryAtCapacity;

  /// No description provided for @memoryCapacityWarning.
  ///
  /// In en, this message translates to:
  /// **'Memory almost full ({percent}%)'**
  String memoryCapacityWarning(int percent);

  /// No description provided for @memoryLastExtracted.
  ///
  /// In en, this message translates to:
  /// **'Last extracted {when}'**
  String memoryLastExtracted(String when);

  /// No description provided for @categoryPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get categoryPreferences;

  /// No description provided for @categoryFacts.
  ///
  /// In en, this message translates to:
  /// **'Facts'**
  String get categoryFacts;

  /// No description provided for @categoryProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get categoryProjects;

  /// No description provided for @categoryPatterns.
  ///
  /// In en, this message translates to:
  /// **'Patterns'**
  String get categoryPatterns;

  /// No description provided for @categoryContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get categoryContext;

  /// No description provided for @researchAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get researchAll;

  /// No description provided for @researchCVE.
  ///
  /// In en, this message translates to:
  /// **'CVE'**
  String get researchCVE;

  /// No description provided for @researchExploit.
  ///
  /// In en, this message translates to:
  /// **'Exploit'**
  String get researchExploit;

  /// No description provided for @researchBugBounty.
  ///
  /// In en, this message translates to:
  /// **'Bug bounty'**
  String get researchBugBounty;

  /// No description provided for @researchMalware.
  ///
  /// In en, this message translates to:
  /// **'Malware'**
  String get researchMalware;

  /// No description provided for @researchPentest.
  ///
  /// In en, this message translates to:
  /// **'Pentest'**
  String get researchPentest;

  /// No description provided for @newResearch.
  ///
  /// In en, this message translates to:
  /// **'New research'**
  String get newResearch;

  /// No description provided for @noResearchYet.
  ///
  /// In en, this message translates to:
  /// **'No research sessions yet'**
  String get noResearchYet;

  /// No description provided for @researchEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Start a new research session to investigate CVEs, exploits, or threats.'**
  String get researchEmptyHint;

  /// No description provided for @sources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sources;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @doneLabel.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneLabel;

  /// No description provided for @projectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsTitle;

  /// No description provided for @freePlan2.
  ///
  /// In en, this message translates to:
  /// **'Free plan'**
  String get freePlan2;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// No description provided for @greetingWithName.
  ///
  /// In en, this message translates to:
  /// **'{period}, {name}'**
  String greetingWithName(String period, String name);

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @noConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noConversations;

  /// No description provided for @promptBrainstorm.
  ///
  /// In en, this message translates to:
  /// **'Brainstorm ideas'**
  String get promptBrainstorm;

  /// No description provided for @promptExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain a concept'**
  String get promptExplain;

  /// No description provided for @promptCode.
  ///
  /// In en, this message translates to:
  /// **'Help me write code'**
  String get promptCode;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'en',
        'es',
        'fr',
        'hi',
        'id',
        'it',
        'ja',
        'ko',
        'nl',
        'pl',
        'pt',
        'ru',
        'th',
        'tr',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppL10nZhHans();
          case 'Hant':
            return AppL10nZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppL10nAr();
    case 'de':
      return AppL10nDe();
    case 'en':
      return AppL10nEn();
    case 'es':
      return AppL10nEs();
    case 'fr':
      return AppL10nFr();
    case 'hi':
      return AppL10nHi();
    case 'id':
      return AppL10nId();
    case 'it':
      return AppL10nIt();
    case 'ja':
      return AppL10nJa();
    case 'ko':
      return AppL10nKo();
    case 'nl':
      return AppL10nNl();
    case 'pl':
      return AppL10nPl();
    case 'pt':
      return AppL10nPt();
    case 'ru':
      return AppL10nRu();
    case 'th':
      return AppL10nTh();
    case 'tr':
      return AppL10nTr();
    case 'vi':
      return AppL10nVi();
    case 'zh':
      return AppL10nZh();
  }

  throw FlutterError(
      'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
