// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppL10nHi extends AppL10n {
  AppL10nHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'साइन इन';

  @override
  String get signUp => 'साइन अप';

  @override
  String get signOut => 'साइन आउट';

  @override
  String get signInToContinue => 'जारी रखने के लिए साइन इन करें';

  @override
  String get createAccount => 'खाता बनाएं';

  @override
  String get joinCyberNeurovaFree => 'CyberNeurova में मुफ्त में शामिल हों';

  @override
  String get email => 'ईमेल';

  @override
  String get password => 'पासवर्ड';

  @override
  String get nameOptional => 'नाम (वैकल्पिक)';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get dontHaveAccount => 'खाता नहीं है? साइन अप करें';

  @override
  String get alreadyHaveAccount => 'पहले से खाता है? साइन इन करें';

  @override
  String get orDivider => 'या';

  @override
  String get continueWithGoogle => 'Google से जारी रखें';

  @override
  String get continueWithApple => 'Apple से जारी रखें';

  @override
  String get enterValidEmail => 'मान्य ईमेल दर्ज करें';

  @override
  String get passwordTooShort => 'पासवर्ड बहुत छोटा है';

  @override
  String get passwordMin8 => 'कम से कम 8 अक्षर';

  @override
  String get enterYourPassword => 'अपना पासवर्ड दर्ज करें';

  @override
  String get resetPassword => 'पासवर्ड रीसेट करें';

  @override
  String get resetPasswordHint =>
      'अपने खाते का ईमेल दर्ज करें और हम आपको पासवर्ड रीसेट करने के लिए एक लिंक भेजेंगे।';

  @override
  String get sendResetLink => 'रीसेट लिंक भेजें';

  @override
  String get backToSignIn => 'साइन इन पर वापस';

  @override
  String get checkYourEmail => 'अपना ईमेल देखें';

  @override
  String resetSentBody(String email) {
    return 'अगर $email के लिए खाता मौजूद है, तो रीसेट लिंक भेज दिया गया है। यदि न दिखे तो स्पैम फ़ोल्डर देखें।';
  }

  @override
  String get verifyEmailTitle => 'अपना ईमेल देखें';

  @override
  String verifyEmailBody(String email) {
    return 'हमने $email पर सत्यापन लिंक भेजा है। अपने खाते को सक्रिय करने के लिए लिंक पर टैप करें, फिर साइन इन करें।';
  }

  @override
  String get ok => 'ठीक है';

  @override
  String get chats => 'चैट';

  @override
  String get images => 'इमेज';

  @override
  String get discover => 'खोजें';

  @override
  String get profile => 'प्रोफ़ाइल';

  @override
  String get noChatsYet => 'अभी तक कोई बातचीत नहीं';

  @override
  String get startChattingHint => 'CyberNeurova AI के साथ चैट करना शुरू करें';

  @override
  String get newConversation => 'नई बातचीत';

  @override
  String get messageInputHint => 'CyberNeurova को मैसेज करें...';

  @override
  String get howCanIHelp => 'मैं आज आपकी कैसे मदद कर सकता हूँ?';

  @override
  String get search => 'खोजें';

  @override
  String get searchChatsHint => 'चैट खोजें…';

  @override
  String get typeToSearchChats => 'अपनी चैट खोजने के लिए टाइप करें';

  @override
  String noChatsMatch(String query) {
    return '\"$query\" से मेल खाने वाली कोई चैट नहीं';
  }

  @override
  String get rename => 'नाम बदलें';

  @override
  String get deleteChat => 'चैट हटाएं';

  @override
  String get deleteChatQuestion => 'चैट हटाएं?';

  @override
  String get cannotBeUndone => 'इसे पूर्ववत नहीं किया जा सकता।';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get delete => 'हटाएं';

  @override
  String get save => 'सहेजें';

  @override
  String get retry => 'फिर से कोशिश करें';

  @override
  String get copiedToClipboard => 'क्लिपबोर्ड पर कॉपी हो गया';

  @override
  String get waitForResponseToFinish => 'जवाब पूरा होने तक प्रतीक्षा करें।';

  @override
  String get noImagesYet => 'अभी तक कोई इमेज नहीं';

  @override
  String get tapGenerateHint => 'अपनी पहली इमेज बनाने के लिए जनरेट पर टैप करें';

  @override
  String get generate => 'जनरेट करें';

  @override
  String get generateImage => 'इमेज जनरेट करें';

  @override
  String get describeImage => 'जिस इमेज को आप चाहते हैं उसका वर्णन करें...';

  @override
  String get yourImageWillAppear => 'आपकी इमेज यहाँ दिखाई देगी';

  @override
  String get starting => 'शुरू हो रहा है...';

  @override
  String generatingPercent(int percent) {
    return 'जनरेट हो रहा है $percent%';
  }

  @override
  String get generateAnother => 'एक और जनरेट करें';

  @override
  String get generationFailed => 'जनरेशन विफल';

  @override
  String get trending => 'ट्रेंडिंग';

  @override
  String get recent => 'हाल का';

  @override
  String get nothingToDiscover => 'अभी खोजने के लिए कुछ नहीं';

  @override
  String get freePlan => 'फ्री प्लान';

  @override
  String get premiumPlan => 'प्रीमियम प्लान';

  @override
  String get proPlan => 'प्रो प्लान';

  @override
  String get proMaxPlan => 'प्रो मैक्स प्लान';

  @override
  String get upgrade => 'अपग्रेड';

  @override
  String get upgradeHint => 'अधिक टोकन और मॉडल के लिए अपग्रेड करें';

  @override
  String get tokenUsage => 'टोकन उपयोग';

  @override
  String get used => 'उपयोग किया गया';

  @override
  String get limit => 'सीमा';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get notifications => 'सूचनाएँ';

  @override
  String get changePassword => 'पासवर्ड बदलें';

  @override
  String get language => 'भाषा';

  @override
  String get account => 'खाता';

  @override
  String get editProfile => 'प्रोफ़ाइल संपादित करें';

  @override
  String get activeSessions => 'सक्रिय सत्र';

  @override
  String get deleteAccount => 'खाता हटाएं';

  @override
  String get deleteAccountConfirm =>
      'अपना खाता स्थायी रूप से हटाएं? इसे पूर्ववत नहीं किया जा सकता।';

  @override
  String get deleteAccountPasswordOptional =>
      'यदि आपने Google या Apple से साइन इन किया है तो इसे खाली छोड़ें।';

  @override
  String get signOutQuestion => 'साइन आउट करें?';

  @override
  String get signOutBody => 'आपको फिर से लॉगिन करना होगा।';

  @override
  String get voiceInput => 'वॉइस इनपुट';

  @override
  String get voiceInputHint =>
      'रिकॉर्ड करने के लिए दबाए रखें, भेजने के लिए छोड़ें।';

  @override
  String get voiceTranscribing => 'ट्रांसक्राइब हो रहा है…';

  @override
  String get voicePermissionDenied => 'माइक्रोफ़ोन अनुमति अस्वीकृत।';

  @override
  String get attach => 'अटैच करें';

  @override
  String get takePhoto => 'फ़ोटो लें';

  @override
  String get fromLibrary => 'गैलरी से';

  @override
  String get uploadingFile => 'अपलोड हो रहा है…';

  @override
  String get shareChat => 'चैट साझा करें';

  @override
  String get visibility => 'दृश्यता';

  @override
  String get visibilityPrivate => 'निजी';

  @override
  String get visibilityShared => 'विशिष्ट लोगों के साथ साझा';

  @override
  String get visibilityPublic => 'सार्वजनिक लिंक';

  @override
  String get shareWithEmail => 'किसी के साथ साझा करें (ईमेल)';

  @override
  String get addPerson => 'जोड़ें';

  @override
  String get copyLink => 'लिंक कॉपी करें';

  @override
  String get linkCopied => 'लिंक कॉपी किया गया';

  @override
  String get errorGeneric => 'कुछ गलत हो गया। कृपया पुनः प्रयास करें।';

  @override
  String get errorNetwork => 'इंटरनेट कनेक्शन नहीं है।';

  @override
  String get errorSessionExpired => 'सत्र समाप्त। कृपया फिर से साइन इन करें।';

  @override
  String errorRateLimited(int seconds) {
    return 'बहुत सारे अनुरोध। $seconds सेकंड में पुनः प्रयास करें।';
  }

  @override
  String get errorQuotaExceeded => 'टोकन कोटा समाप्त।';

  @override
  String get errorServer => 'सर्वर त्रुटि। बाद में पुनः प्रयास करें।';

  @override
  String get couldNotOpenBrowser => 'ब्राउज़र नहीं खुल सका।';

  @override
  String get comingSoon => 'जल्द आ रहा है';

  @override
  String get newChat => 'नई चैट';

  @override
  String get media => 'मीडिया';

  @override
  String get research => 'रिसर्च';

  @override
  String get recents => 'हाल का';

  @override
  String get chatsWillAppearHere => 'आपकी चैट यहाँ दिखाई देंगी';

  @override
  String get billing => 'बिलिंग';

  @override
  String get usageLabel => 'उपयोग';

  @override
  String get customPrompts => 'कस्टम प्रॉम्प्ट';

  @override
  String get memory => 'मेमोरी';

  @override
  String get capabilities => 'क्षमताएँ';

  @override
  String get designLab => 'डिज़ाइन लैब';

  @override
  String get skills => 'कौशल';

  @override
  String get tools => 'उपकरण';

  @override
  String get premiumRequired =>
      'प्रीमियम सुविधा — सक्षम करने के लिए अपग्रेड करें';

  @override
  String get memoryEmptyTitle => 'अभी कोई यादें नहीं';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova आपकी चैट का महत्वपूर्ण संदर्भ यहाँ सहेजेगा।';

  @override
  String get memoryAtCapacity =>
      'मेमोरी पूरी — सबसे पुरानी प्रविष्टियाँ बदली जाएँगी।';

  @override
  String memoryCapacityWarning(int percent) {
    return 'मेमोरी लगभग भरी ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'अंतिम बार निकाला गया $when';
  }

  @override
  String get categoryPreferences => 'प्राथमिकताएँ';

  @override
  String get categoryFacts => 'तथ्य';

  @override
  String get categoryProjects => 'प्रोजेक्ट';

  @override
  String get categoryPatterns => 'पैटर्न';

  @override
  String get categoryContext => 'संदर्भ';

  @override
  String get researchAll => 'सभी';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'एक्सप्लॉइट';

  @override
  String get researchBugBounty => 'बग बाउंटी';

  @override
  String get researchMalware => 'मैलवेयर';

  @override
  String get researchPentest => 'पेंटेस्ट';

  @override
  String get newResearch => 'नया रिसर्च';

  @override
  String get noResearchYet => 'अभी कोई रिसर्च नहीं';

  @override
  String get researchEmptyHint =>
      'CVE, एक्सप्लॉइट या खतरों की जाँच के लिए नया रिसर्च शुरू करें।';

  @override
  String get sources => 'स्रोत';

  @override
  String get close => 'बंद करें';

  @override
  String get doneLabel => 'पूर्ण';

  @override
  String get projectsTitle => 'प्रोजेक्ट';

  @override
  String get freePlan2 => 'मुफ़्त प्लान';

  @override
  String get greetingMorning => 'शुभ प्रभात';

  @override
  String get greetingAfternoon => 'नमस्ते';

  @override
  String get greetingEvening => 'शुभ संध्या';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'सिस्टम';

  @override
  String get noConversations => 'अभी कोई बातचीत नहीं';

  @override
  String get promptBrainstorm => 'विचार-मंथन';

  @override
  String get promptExplain => 'एक अवधारणा समझाएँ';

  @override
  String get promptCode => 'कोड लिखने में मदद करें';
}
