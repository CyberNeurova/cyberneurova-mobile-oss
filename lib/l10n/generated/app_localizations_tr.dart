// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppL10nTr extends AppL10n {
  AppL10nTr([String locale = 'tr']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Giriş yap';

  @override
  String get signUp => 'Kaydol';

  @override
  String get signOut => 'Çıkış yap';

  @override
  String get signInToContinue => 'Devam etmek için giriş yapın';

  @override
  String get createAccount => 'Hesap oluştur';

  @override
  String get joinCyberNeurovaFree => 'CyberNeurova\'ya ücretsiz katıl';

  @override
  String get email => 'E-posta';

  @override
  String get password => 'Şifre';

  @override
  String get nameOptional => 'Ad (isteğe bağlı)';

  @override
  String get forgotPassword => 'Şifrenizi mi unuttunuz?';

  @override
  String get dontHaveAccount => 'Hesabınız yok mu? Kaydolun';

  @override
  String get alreadyHaveAccount => 'Zaten hesabınız var mı? Giriş yapın';

  @override
  String get orDivider => 'VEYA';

  @override
  String get continueWithGoogle => 'Google ile devam et';

  @override
  String get continueWithApple => 'Apple ile devam et';

  @override
  String get enterValidEmail => 'Geçerli bir e-posta girin';

  @override
  String get passwordTooShort => 'Şifre çok kısa';

  @override
  String get passwordMin8 => 'En az 8 karakter';

  @override
  String get enterYourPassword => 'Şifrenizi girin';

  @override
  String get resetPassword => 'Şifreyi sıfırla';

  @override
  String get resetPasswordHint =>
      'Hesabınızın e-postasını girin, şifrenizi sıfırlamanız için bir bağlantı gönderelim.';

  @override
  String get sendResetLink => 'Bağlantı gönder';

  @override
  String get backToSignIn => 'Girişe dön';

  @override
  String get checkYourEmail => 'E-postanızı kontrol edin';

  @override
  String resetSentBody(String email) {
    return '$email için bir hesap varsa, sıfırlama bağlantısı yolda. Göremiyorsanız spam klasörünü kontrol edin.';
  }

  @override
  String get verifyEmailTitle => 'E-postanızı kontrol edin';

  @override
  String verifyEmailBody(String email) {
    return '$email adresine doğrulama bağlantısı gönderdik. Hesabınızı etkinleştirmek için bağlantıya dokunun, ardından giriş yapın.';
  }

  @override
  String get ok => 'Tamam';

  @override
  String get chats => 'Sohbetler';

  @override
  String get images => 'Görseller';

  @override
  String get discover => 'Keşfet';

  @override
  String get profile => 'Profil';

  @override
  String get noChatsYet => 'Henüz sohbet yok';

  @override
  String get startChattingHint => 'CyberNeurova AI ile sohbete başlayın';

  @override
  String get newConversation => 'Yeni sohbet';

  @override
  String get messageInputHint => 'CyberNeurova\'ya mesaj...';

  @override
  String get howCanIHelp => 'Bugün size nasıl yardımcı olabilirim?';

  @override
  String get search => 'Ara';

  @override
  String get searchChatsHint => 'Sohbetlerde ara…';

  @override
  String get typeToSearchChats => 'Sohbetlerinizde aramak için yazın';

  @override
  String noChatsMatch(String query) {
    return '\"$query\" ile eşleşen sohbet yok';
  }

  @override
  String get rename => 'Yeniden adlandır';

  @override
  String get deleteChat => 'Sohbeti sil';

  @override
  String get deleteChatQuestion => 'Sohbet silinsin mi?';

  @override
  String get cannotBeUndone => 'Bu işlem geri alınamaz.';

  @override
  String get cancel => 'İptal';

  @override
  String get delete => 'Sil';

  @override
  String get save => 'Kaydet';

  @override
  String get retry => 'Tekrar dene';

  @override
  String get copiedToClipboard => 'Panoya kopyalandı';

  @override
  String get waitForResponseToFinish => 'Yanıt bitene kadar bekleyin.';

  @override
  String get noImagesYet => 'Henüz görsel yok';

  @override
  String get tapGenerateHint =>
      'İlk görselinizi oluşturmak için Oluştur\'a dokunun';

  @override
  String get generate => 'Oluştur';

  @override
  String get generateImage => 'Görsel oluştur';

  @override
  String get describeImage => 'İstediğiniz görseli tanımlayın...';

  @override
  String get yourImageWillAppear => 'Görseliniz burada görünecek';

  @override
  String get starting => 'Başlatılıyor...';

  @override
  String generatingPercent(int percent) {
    return 'Oluşturuluyor %$percent';
  }

  @override
  String get generateAnother => 'Yeni bir tane oluştur';

  @override
  String get generationFailed => 'Oluşturma başarısız';

  @override
  String get trending => 'Popüler';

  @override
  String get recent => 'Son';

  @override
  String get nothingToDiscover => 'Henüz keşfedilecek bir şey yok';

  @override
  String get freePlan => 'Ücretsiz Plan';

  @override
  String get premiumPlan => 'Premium Plan';

  @override
  String get proPlan => 'Pro Plan';

  @override
  String get proMaxPlan => 'Pro Max Plan';

  @override
  String get upgrade => 'Yükselt';

  @override
  String get upgradeHint => 'Daha fazla token ve model için yükseltin';

  @override
  String get tokenUsage => 'Token kullanımı';

  @override
  String get used => 'kullanılan';

  @override
  String get limit => 'limit';

  @override
  String get settings => 'Ayarlar';

  @override
  String get notifications => 'Bildirimler';

  @override
  String get changePassword => 'Şifreyi değiştir';

  @override
  String get language => 'Dil';

  @override
  String get account => 'Hesap';

  @override
  String get editProfile => 'Profili düzenle';

  @override
  String get activeSessions => 'Etkin oturumlar';

  @override
  String get deleteAccount => 'Hesabı sil';

  @override
  String get deleteAccountConfirm =>
      'Hesabınız kalıcı olarak silinsin mi? Bu işlem geri alınamaz.';

  @override
  String get deleteAccountPasswordOptional =>
      'Google veya Apple ile giriş yaptıysanız boş bırakın.';

  @override
  String get signOutQuestion => 'Çıkış yapılsın mı?';

  @override
  String get signOutBody => 'Tekrar giriş yapmanız gerekecek.';

  @override
  String get voiceInput => 'Sesli giriş';

  @override
  String get voiceInputHint =>
      'Kaydetmek için basılı tutun, göndermek için bırakın.';

  @override
  String get voiceTranscribing => 'Yazıya dökülüyor…';

  @override
  String get voicePermissionDenied => 'Mikrofon izni reddedildi.';

  @override
  String get attach => 'Ekle';

  @override
  String get takePhoto => 'Fotoğraf çek';

  @override
  String get fromLibrary => 'Galeriden';

  @override
  String get uploadingFile => 'Yükleniyor…';

  @override
  String get shareChat => 'Sohbeti paylaş';

  @override
  String get visibility => 'Görünürlük';

  @override
  String get visibilityPrivate => 'Özel';

  @override
  String get visibilityShared => 'Belirli kişilerle paylaşıldı';

  @override
  String get visibilityPublic => 'Herkese açık bağlantı';

  @override
  String get shareWithEmail => 'Birisiyle paylaş (e-posta)';

  @override
  String get addPerson => 'Ekle';

  @override
  String get copyLink => 'Bağlantıyı kopyala';

  @override
  String get linkCopied => 'Bağlantı kopyalandı';

  @override
  String get errorGeneric => 'Bir şeyler ters gitti. Lütfen tekrar deneyin.';

  @override
  String get errorNetwork => 'İnternet bağlantısı yok.';

  @override
  String get errorSessionExpired =>
      'Oturum sona erdi. Lütfen tekrar giriş yapın.';

  @override
  String errorRateLimited(int seconds) {
    return 'Çok fazla istek. $seconds sn içinde tekrar deneyin.';
  }

  @override
  String get errorQuotaExceeded => 'Token kotası aşıldı.';

  @override
  String get errorServer => 'Sunucu hatası. Daha sonra deneyin.';

  @override
  String get couldNotOpenBrowser => 'Tarayıcı açılamadı.';

  @override
  String get comingSoon => 'Yakında';

  @override
  String get newChat => 'Yeni sohbet';

  @override
  String get media => 'Medya';

  @override
  String get research => 'Araştırma';

  @override
  String get recents => 'Son kullanılanlar';

  @override
  String get chatsWillAppearHere => 'Sohbetleriniz burada görünecek';

  @override
  String get billing => 'Faturalandırma';

  @override
  String get usageLabel => 'Kullanım';

  @override
  String get customPrompts => 'Özel istemler';

  @override
  String get memory => 'Hafıza';

  @override
  String get capabilities => 'Yetenekler';

  @override
  String get designLab => 'Tasarım Laboratuvarı';

  @override
  String get skills => 'Beceriler';

  @override
  String get tools => 'Araçlar';

  @override
  String get premiumRequired =>
      'Premium özellik — etkinleştirmek için yükseltin';

  @override
  String get memoryEmptyTitle => 'Henüz hafıza yok';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova sohbetlerinizden önemli bağlamı burada saklayacak.';

  @override
  String get memoryAtCapacity =>
      'Hafıza dolu — en eski girişler değiştirilecek.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Hafıza neredeyse dolu ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Son çıkarma $when';
  }

  @override
  String get categoryPreferences => 'Tercihler';

  @override
  String get categoryFacts => 'Gerçekler';

  @override
  String get categoryProjects => 'Projeler';

  @override
  String get categoryPatterns => 'Desenler';

  @override
  String get categoryContext => 'Bağlam';

  @override
  String get researchAll => 'Tümü';

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
  String get newResearch => 'Yeni araştırma';

  @override
  String get noResearchYet => 'Henüz araştırma yok';

  @override
  String get researchEmptyHint =>
      'CVE, exploit veya tehditleri araştırmak için yeni bir oturum başlatın.';

  @override
  String get sources => 'Kaynaklar';

  @override
  String get close => 'Kapat';

  @override
  String get doneLabel => 'Tamam';

  @override
  String get projectsTitle => 'Projeler';

  @override
  String get freePlan2 => 'Ücretsiz plan';

  @override
  String get greetingMorning => 'Günaydın';

  @override
  String get greetingAfternoon => 'İyi günler';

  @override
  String get greetingEvening => 'İyi akşamlar';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Sistem';

  @override
  String get noConversations => 'Henüz konuşma yok';

  @override
  String get promptBrainstorm => 'Fikir üret';

  @override
  String get promptExplain => 'Bir kavramı açıkla';

  @override
  String get promptCode => 'Kod yazmama yardım et';
}
