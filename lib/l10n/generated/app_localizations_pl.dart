// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppL10nPl extends AppL10n {
  AppL10nPl([String locale = 'pl']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Zaloguj się';

  @override
  String get signUp => 'Zarejestruj się';

  @override
  String get signOut => 'Wyloguj się';

  @override
  String get signInToContinue => 'Zaloguj się, aby kontynuować';

  @override
  String get createAccount => 'Utwórz konto';

  @override
  String get joinCyberNeurovaFree => 'Dołącz do CyberNeurova za darmo';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Hasło';

  @override
  String get nameOptional => 'Imię (opcjonalnie)';

  @override
  String get forgotPassword => 'Nie pamiętasz hasła?';

  @override
  String get dontHaveAccount => 'Nie masz konta? Zarejestruj się';

  @override
  String get alreadyHaveAccount => 'Masz już konto? Zaloguj się';

  @override
  String get orDivider => 'LUB';

  @override
  String get continueWithGoogle => 'Kontynuuj z Google';

  @override
  String get continueWithApple => 'Kontynuuj z Apple';

  @override
  String get enterValidEmail => 'Wprowadź poprawny e-mail';

  @override
  String get passwordTooShort => 'Hasło jest za krótkie';

  @override
  String get passwordMin8 => 'Co najmniej 8 znaków';

  @override
  String get enterYourPassword => 'Wprowadź hasło';

  @override
  String get resetPassword => 'Zresetuj hasło';

  @override
  String get resetPasswordHint =>
      'Wpisz e-mail swojego konta, a wyślemy link do zresetowania hasła.';

  @override
  String get sendResetLink => 'Wyślij link';

  @override
  String get backToSignIn => 'Powrót do logowania';

  @override
  String get checkYourEmail => 'Sprawdź swój e-mail';

  @override
  String resetSentBody(String email) {
    return 'Jeśli konto dla $email istnieje, link do resetowania jest już w drodze. Sprawdź folder ze spamem, jeśli go nie widzisz.';
  }

  @override
  String get verifyEmailTitle => 'Sprawdź swój e-mail';

  @override
  String verifyEmailBody(String email) {
    return 'Wysłaliśmy link weryfikacyjny na $email. Dotknij linku, aby aktywować konto, a następnie zaloguj się.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Czaty';

  @override
  String get images => 'Obrazy';

  @override
  String get discover => 'Odkrywaj';

  @override
  String get profile => 'Profil';

  @override
  String get noChatsYet => 'Brak rozmów';

  @override
  String get startChattingHint => 'Zacznij rozmowę z CyberNeurova AI';

  @override
  String get newConversation => 'Nowa rozmowa';

  @override
  String get messageInputHint => 'Wiadomość do CyberNeurova...';

  @override
  String get howCanIHelp => 'Jak mogę dziś pomóc?';

  @override
  String get search => 'Szukaj';

  @override
  String get searchChatsHint => 'Szukaj czatów…';

  @override
  String get typeToSearchChats => 'Wpisz, aby szukać w swoich czatach';

  @override
  String noChatsMatch(String query) {
    return 'Brak czatów dla „$query\"';
  }

  @override
  String get rename => 'Zmień nazwę';

  @override
  String get deleteChat => 'Usuń czat';

  @override
  String get deleteChatQuestion => 'Usunąć czat?';

  @override
  String get cannotBeUndone => 'Tej operacji nie można cofnąć.';

  @override
  String get cancel => 'Anuluj';

  @override
  String get delete => 'Usuń';

  @override
  String get save => 'Zapisz';

  @override
  String get retry => 'Spróbuj ponownie';

  @override
  String get copiedToClipboard => 'Skopiowano do schowka';

  @override
  String get waitForResponseToFinish => 'Poczekaj na zakończenie odpowiedzi.';

  @override
  String get noImagesYet => 'Brak obrazów';

  @override
  String get tapGenerateHint => 'Dotknij Generuj, aby utworzyć pierwszy obraz';

  @override
  String get generate => 'Generuj';

  @override
  String get generateImage => 'Generuj obraz';

  @override
  String get describeImage => 'Opisz obraz, którego chcesz...';

  @override
  String get yourImageWillAppear => 'Twój obraz pojawi się tutaj';

  @override
  String get starting => 'Uruchamianie...';

  @override
  String generatingPercent(int percent) {
    return 'Generowanie $percent%';
  }

  @override
  String get generateAnother => 'Wygeneruj kolejny';

  @override
  String get generationFailed => 'Generowanie nie powiodło się';

  @override
  String get trending => 'Na czasie';

  @override
  String get recent => 'Ostatnie';

  @override
  String get nothingToDiscover => 'Nie ma jeszcze nic do odkrycia';

  @override
  String get freePlan => 'Plan Bezpłatny';

  @override
  String get premiumPlan => 'Plan Premium';

  @override
  String get proPlan => 'Plan Pro';

  @override
  String get proMaxPlan => 'Plan Pro Max';

  @override
  String get upgrade => 'Ulepsz';

  @override
  String get upgradeHint => 'Ulepsz, aby uzyskać więcej tokenów i modeli';

  @override
  String get tokenUsage => 'Zużycie tokenów';

  @override
  String get used => 'wykorzystano';

  @override
  String get limit => 'limit';

  @override
  String get settings => 'Ustawienia';

  @override
  String get notifications => 'Powiadomienia';

  @override
  String get changePassword => 'Zmień hasło';

  @override
  String get language => 'Język';

  @override
  String get account => 'Konto';

  @override
  String get editProfile => 'Edytuj profil';

  @override
  String get activeSessions => 'Aktywne sesje';

  @override
  String get deleteAccount => 'Usuń konto';

  @override
  String get deleteAccountConfirm =>
      'Trwale usunąć konto? Tej operacji nie można cofnąć.';

  @override
  String get deleteAccountPasswordOptional =>
      'Pozostaw puste, jeśli logujesz się przez Google lub Apple.';

  @override
  String get signOutQuestion => 'Wylogować się?';

  @override
  String get signOutBody => 'Trzeba będzie zalogować się ponownie.';

  @override
  String get voiceInput => 'Wprowadzanie głosowe';

  @override
  String get voiceInputHint => 'Przytrzymaj, aby nagrać, zwolnij, aby wysłać.';

  @override
  String get voiceTranscribing => 'Transkrybowanie…';

  @override
  String get voicePermissionDenied => 'Odmowa dostępu do mikrofonu.';

  @override
  String get attach => 'Załącz';

  @override
  String get takePhoto => 'Zrób zdjęcie';

  @override
  String get fromLibrary => 'Z galerii';

  @override
  String get uploadingFile => 'Przesyłanie…';

  @override
  String get shareChat => 'Udostępnij czat';

  @override
  String get visibility => 'Widoczność';

  @override
  String get visibilityPrivate => 'Prywatny';

  @override
  String get visibilityShared => 'Udostępniony określonym osobom';

  @override
  String get visibilityPublic => 'Link publiczny';

  @override
  String get shareWithEmail => 'Udostępnij komuś (e-mail)';

  @override
  String get addPerson => 'Dodaj';

  @override
  String get copyLink => 'Kopiuj link';

  @override
  String get linkCopied => 'Link skopiowany';

  @override
  String get errorGeneric => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String get errorNetwork => 'Brak połączenia z internetem.';

  @override
  String get errorSessionExpired => 'Sesja wygasła. Zaloguj się ponownie.';

  @override
  String errorRateLimited(int seconds) {
    return 'Zbyt wiele żądań. Spróbuj za $seconds s.';
  }

  @override
  String get errorQuotaExceeded => 'Limit tokenów przekroczony.';

  @override
  String get errorServer => 'Błąd serwera. Spróbuj później.';

  @override
  String get couldNotOpenBrowser => 'Nie udało się otworzyć przeglądarki.';

  @override
  String get comingSoon => 'Wkrótce';

  @override
  String get newChat => 'Nowy czat';

  @override
  String get media => 'Media';

  @override
  String get research => 'Badania';

  @override
  String get recents => 'Ostatnie';

  @override
  String get chatsWillAppearHere => 'Twoje czaty pojawią się tutaj';

  @override
  String get billing => 'Rozliczenia';

  @override
  String get usageLabel => 'Użycie';

  @override
  String get customPrompts => 'Własne podpowiedzi';

  @override
  String get memory => 'Pamięć';

  @override
  String get capabilities => 'Możliwości';

  @override
  String get designLab => 'Laboratorium designu';

  @override
  String get skills => 'Umiejętności';

  @override
  String get tools => 'Narzędzia';

  @override
  String get premiumRequired => 'Funkcja Premium — ulepsz, aby włączyć';

  @override
  String get memoryEmptyTitle => 'Brak wspomnień';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova zapisze tu ważny kontekst z Twoich czatów.';

  @override
  String get memoryAtCapacity =>
      'Pamięć pełna — najstarsze wpisy zostaną zastąpione.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Pamięć prawie pełna ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Ostatnio wyodrębniono $when';
  }

  @override
  String get categoryPreferences => 'Preferencje';

  @override
  String get categoryFacts => 'Fakty';

  @override
  String get categoryProjects => 'Projekty';

  @override
  String get categoryPatterns => 'Wzorce';

  @override
  String get categoryContext => 'Kontekst';

  @override
  String get researchAll => 'Wszystko';

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
  String get newResearch => 'Nowe badanie';

  @override
  String get noResearchYet => 'Brak badań';

  @override
  String get researchEmptyHint =>
      'Rozpocznij nowe badanie CVE, exploitów lub zagrożeń.';

  @override
  String get sources => 'Źródła';

  @override
  String get close => 'Zamknij';

  @override
  String get doneLabel => 'Gotowe';

  @override
  String get projectsTitle => 'Projekty';

  @override
  String get freePlan2 => 'Plan darmowy';

  @override
  String get greetingMorning => 'Dzień dobry';

  @override
  String get greetingAfternoon => 'Dzień dobry';

  @override
  String get greetingEvening => 'Dobry wieczór';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'System';

  @override
  String get noConversations => 'Brak rozmów';

  @override
  String get promptBrainstorm => 'Burza mózgów';

  @override
  String get promptExplain => 'Wyjaśnij koncept';

  @override
  String get promptCode => 'Pomóż mi pisać kod';
}
