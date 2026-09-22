// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppL10nAr extends AppL10n {
  AppL10nAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get signUp => 'إنشاء حساب';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get signInToContinue => 'سجّل الدخول للمتابعة';

  @override
  String get createAccount => 'إنشاء حساب';

  @override
  String get joinCyberNeurovaFree => 'انضم إلى CyberNeurova مجانًا';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get password => 'كلمة المرور';

  @override
  String get nameOptional => 'الاسم (اختياري)';

  @override
  String get forgotPassword => 'هل نسيت كلمة المرور؟';

  @override
  String get dontHaveAccount => 'ليس لديك حساب؟ سجّل الآن';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟ سجّل الدخول';

  @override
  String get orDivider => 'أو';

  @override
  String get continueWithGoogle => 'المتابعة باستخدام Google';

  @override
  String get continueWithApple => 'المتابعة باستخدام Apple';

  @override
  String get enterValidEmail => 'أدخل بريدًا إلكترونيًا صالحًا';

  @override
  String get passwordTooShort => 'كلمة المرور قصيرة جدًا';

  @override
  String get passwordMin8 => '8 أحرف على الأقل';

  @override
  String get enterYourPassword => 'أدخل كلمة المرور';

  @override
  String get resetPassword => 'إعادة تعيين كلمة المرور';

  @override
  String get resetPasswordHint =>
      'أدخل بريد حسابك الإلكتروني وسنرسل لك رابطًا لإعادة تعيين كلمة المرور.';

  @override
  String get sendResetLink => 'إرسال الرابط';

  @override
  String get backToSignIn => 'العودة إلى تسجيل الدخول';

  @override
  String get checkYourEmail => 'تحقق من بريدك الإلكتروني';

  @override
  String resetSentBody(String email) {
    return 'إذا كان هناك حساب لـ $email، فقد أُرسل رابط إعادة التعيين. تحقق من مجلد البريد المزعج إذا لم تجده.';
  }

  @override
  String get verifyEmailTitle => 'تحقق من بريدك الإلكتروني';

  @override
  String verifyEmailBody(String email) {
    return 'أرسلنا رابط تحقق إلى $email. اضغط على الرابط لتفعيل حسابك ثم سجّل الدخول.';
  }

  @override
  String get ok => 'موافق';

  @override
  String get chats => 'المحادثات';

  @override
  String get images => 'الصور';

  @override
  String get discover => 'استكشاف';

  @override
  String get profile => 'الملف الشخصي';

  @override
  String get noChatsYet => 'لا توجد محادثات بعد';

  @override
  String get startChattingHint => 'ابدأ الدردشة مع CyberNeurova AI';

  @override
  String get newConversation => 'محادثة جديدة';

  @override
  String get messageInputHint => 'رسالة إلى CyberNeurova...';

  @override
  String get howCanIHelp => 'كيف يمكنني مساعدتك اليوم؟';

  @override
  String get search => 'بحث';

  @override
  String get searchChatsHint => 'ابحث في المحادثات…';

  @override
  String get typeToSearchChats => 'اكتب للبحث في محادثاتك';

  @override
  String noChatsMatch(String query) {
    return 'لا توجد محادثات مطابقة لـ \"$query\"';
  }

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get deleteChat => 'حذف المحادثة';

  @override
  String get deleteChatQuestion => 'حذف المحادثة؟';

  @override
  String get cannotBeUndone => 'لا يمكن التراجع عن هذا.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get save => 'حفظ';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get copiedToClipboard => 'تم النسخ إلى الحافظة';

  @override
  String get waitForResponseToFinish => 'انتظر حتى ينتهي الرد.';

  @override
  String get noImagesYet => 'لا توجد صور بعد';

  @override
  String get tapGenerateHint => 'اضغط على «إنشاء» لإنشاء صورتك الأولى';

  @override
  String get generate => 'إنشاء';

  @override
  String get generateImage => 'إنشاء صورة';

  @override
  String get describeImage => 'صف الصورة التي تريدها...';

  @override
  String get yourImageWillAppear => 'ستظهر صورتك هنا';

  @override
  String get starting => 'جارٍ البدء...';

  @override
  String generatingPercent(int percent) {
    return 'جارٍ الإنشاء $percent%';
  }

  @override
  String get generateAnother => 'إنشاء صورة أخرى';

  @override
  String get generationFailed => 'فشل الإنشاء';

  @override
  String get trending => 'الأكثر رواجًا';

  @override
  String get recent => 'حديث';

  @override
  String get nothingToDiscover => 'لا يوجد شيء للاستكشاف بعد';

  @override
  String get freePlan => 'الخطة المجانية';

  @override
  String get premiumPlan => 'خطة Premium';

  @override
  String get proPlan => 'خطة Pro';

  @override
  String get proMaxPlan => 'خطة Pro Max';

  @override
  String get upgrade => 'ترقية';

  @override
  String get upgradeHint => 'ترقية للحصول على مزيد من التوكنات والنماذج';

  @override
  String get tokenUsage => 'استخدام التوكنات';

  @override
  String get used => 'مستخدم';

  @override
  String get limit => 'الحد';

  @override
  String get settings => 'الإعدادات';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get changePassword => 'تغيير كلمة المرور';

  @override
  String get language => 'اللغة';

  @override
  String get account => 'الحساب';

  @override
  String get editProfile => 'تعديل الملف الشخصي';

  @override
  String get activeSessions => 'الجلسات النشطة';

  @override
  String get deleteAccount => 'حذف الحساب';

  @override
  String get deleteAccountConfirm =>
      'حذف حسابك نهائيًا؟ لا يمكن التراجع عن هذا.';

  @override
  String get deleteAccountPasswordOptional =>
      'اتركه فارغًا إذا سجّلت الدخول باستخدام Google أو Apple.';

  @override
  String get signOutQuestion => 'تسجيل الخروج؟';

  @override
  String get signOutBody => 'ستحتاج إلى تسجيل الدخول مرة أخرى.';

  @override
  String get voiceInput => 'إدخال صوتي';

  @override
  String get voiceInputHint => 'اضغط مطولًا للتسجيل واترك للإرسال.';

  @override
  String get voiceTranscribing => 'جارٍ النسخ…';

  @override
  String get voicePermissionDenied => 'تم رفض إذن الميكروفون.';

  @override
  String get attach => 'إرفاق';

  @override
  String get takePhoto => 'التقاط صورة';

  @override
  String get fromLibrary => 'من المكتبة';

  @override
  String get uploadingFile => 'جارٍ الرفع…';

  @override
  String get shareChat => 'مشاركة المحادثة';

  @override
  String get visibility => 'الرؤية';

  @override
  String get visibilityPrivate => 'خاصة';

  @override
  String get visibilityShared => 'مشاركة مع أشخاص محددين';

  @override
  String get visibilityPublic => 'رابط عام';

  @override
  String get shareWithEmail => 'مشاركة مع شخص (بالبريد الإلكتروني)';

  @override
  String get addPerson => 'إضافة';

  @override
  String get copyLink => 'نسخ الرابط';

  @override
  String get linkCopied => 'تم نسخ الرابط';

  @override
  String get errorGeneric => 'حدث خطأ ما. حاول مرة أخرى.';

  @override
  String get errorNetwork => 'لا يوجد اتصال بالإنترنت.';

  @override
  String get errorSessionExpired => 'انتهت الجلسة. سجّل الدخول مرة أخرى.';

  @override
  String errorRateLimited(int seconds) {
    return 'طلبات كثيرة جدًا. حاول مرة أخرى خلال $seconds ث.';
  }

  @override
  String get errorQuotaExceeded => 'تم تجاوز حصة التوكنات.';

  @override
  String get errorServer => 'خطأ في الخادم. حاول لاحقًا.';

  @override
  String get couldNotOpenBrowser => 'تعذّر فتح المتصفح.';

  @override
  String get comingSoon => 'قريبًا';

  @override
  String get newChat => 'محادثة جديدة';

  @override
  String get media => 'الوسائط';

  @override
  String get research => 'بحث';

  @override
  String get recents => 'الأخيرة';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => 'ستظهر محادثاتك هنا';

  @override
  String get billing => 'الفوترة';

  @override
  String get usageLabel => 'الاستخدام';

  @override
  String get customPrompts => 'موجهات مخصصة';

  @override
  String get memory => 'الذاكرة';

  @override
  String get capabilities => 'القدرات';

  @override
  String get designLab => 'مختبر التصميم';

  @override
  String get skills => 'المهارات';

  @override
  String get tools => 'الأدوات';

  @override
  String get premiumRequired => 'ميزة بريميوم — قم بالترقية للتفعيل';

  @override
  String get memoryEmptyTitle => 'لا توجد ذكريات بعد';

  @override
  String get memoryEmptyHint =>
      'ستحفظ CyberNeurova هنا السياق المهم من محادثاتك.';

  @override
  String get memoryAtCapacity =>
      'الذاكرة ممتلئة — سيتم استبدال أقدم الإدخالات.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'الذاكرة شبه ممتلئة ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'آخر استخراج $when';
  }

  @override
  String get categoryPreferences => 'التفضيلات';

  @override
  String get categoryFacts => 'الحقائق';

  @override
  String get categoryProjects => 'المشاريع';

  @override
  String get categoryPatterns => 'الأنماط';

  @override
  String get categoryContext => 'السياق';

  @override
  String get researchAll => 'الكل';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'استغلال';

  @override
  String get researchBugBounty => 'مكافأة الأخطاء';

  @override
  String get researchMalware => 'برامج ضارة';

  @override
  String get researchPentest => 'اختبار اختراق';

  @override
  String get newResearch => 'بحث جديد';

  @override
  String get noResearchYet => 'لا توجد جلسات بحث بعد';

  @override
  String get researchEmptyHint =>
      'ابدأ بحثًا جديدًا للتحقيق في CVE أو الثغرات أو التهديدات.';

  @override
  String get sources => 'المصادر';

  @override
  String get close => 'إغلاق';

  @override
  String get doneLabel => 'تم';

  @override
  String get projectsTitle => 'المشاريع';

  @override
  String get freePlan2 => 'الخطة المجانية';

  @override
  String get greetingMorning => 'صباح الخير';

  @override
  String get greetingAfternoon => 'مساء الخير';

  @override
  String get greetingEvening => 'مساء الخير';

  @override
  String greetingWithName(String period, String name) {
    return '$period، $name';
  }

  @override
  String get system => 'النظام';

  @override
  String get noConversations => 'لا توجد محادثات بعد';

  @override
  String get promptBrainstorm => 'عصف ذهني للأفكار';

  @override
  String get promptExplain => 'شرح مفهوم';

  @override
  String get promptCode => 'ساعدني في كتابة الكود';
}
