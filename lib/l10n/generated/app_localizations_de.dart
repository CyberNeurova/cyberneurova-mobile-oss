// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppL10nDe extends AppL10n {
  AppL10nDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Anmelden';

  @override
  String get signUp => 'Registrieren';

  @override
  String get signOut => 'Abmelden';

  @override
  String get signInToContinue => 'Melde dich an, um fortzufahren';

  @override
  String get createAccount => 'Konto erstellen';

  @override
  String get joinCyberNeurovaFree => 'Tritt CyberNeurova kostenlos bei';

  @override
  String get email => 'E-Mail';

  @override
  String get password => 'Passwort';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String get forgotPassword => 'Passwort vergessen?';

  @override
  String get dontHaveAccount => 'Noch kein Konto? Registrieren';

  @override
  String get alreadyHaveAccount => 'Bereits ein Konto? Anmelden';

  @override
  String get orDivider => 'ODER';

  @override
  String get continueWithGoogle => 'Mit Google fortfahren';

  @override
  String get continueWithApple => 'Mit Apple fortfahren';

  @override
  String get enterValidEmail => 'Gültige E-Mail eingeben';

  @override
  String get passwordTooShort => 'Passwort zu kurz';

  @override
  String get passwordMin8 => 'Mindestens 8 Zeichen';

  @override
  String get enterYourPassword => 'Passwort eingeben';

  @override
  String get resetPassword => 'Passwort zurücksetzen';

  @override
  String get resetPasswordHint =>
      'Gib die E-Mail deines Kontos ein und wir senden dir einen Link zum Zurücksetzen.';

  @override
  String get sendResetLink => 'Link senden';

  @override
  String get backToSignIn => 'Zurück zur Anmeldung';

  @override
  String get checkYourEmail => 'Prüfe deine E-Mails';

  @override
  String resetSentBody(String email) {
    return 'Wenn ein Konto für $email existiert, ist ein Reset-Link unterwegs. Prüfe den Spam-Ordner, falls du ihn nicht siehst.';
  }

  @override
  String get verifyEmailTitle => 'Prüfe deine E-Mails';

  @override
  String verifyEmailBody(String email) {
    return 'Wir haben einen Bestätigungslink an $email gesendet. Tippe auf den Link, um dein Konto zu aktivieren, und melde dich dann an.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Chats';

  @override
  String get images => 'Bilder';

  @override
  String get discover => 'Entdecken';

  @override
  String get profile => 'Profil';

  @override
  String get noChatsYet => 'Noch keine Unterhaltungen';

  @override
  String get startChattingHint => 'Starte einen Chat mit CyberNeurova AI';

  @override
  String get newConversation => 'Neue Unterhaltung';

  @override
  String get messageInputHint => 'Nachricht an CyberNeurova...';

  @override
  String get howCanIHelp => 'Wie kann ich dir heute helfen?';

  @override
  String get search => 'Suchen';

  @override
  String get searchChatsHint => 'Chats suchen…';

  @override
  String get typeToSearchChats => 'Tippe, um Chats zu durchsuchen';

  @override
  String noChatsMatch(String query) {
    return 'Keine Chats für „$query\"';
  }

  @override
  String get rename => 'Umbenennen';

  @override
  String get deleteChat => 'Chat löschen';

  @override
  String get deleteChatQuestion => 'Chat löschen?';

  @override
  String get cannotBeUndone => 'Dies kann nicht rückgängig gemacht werden.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get save => 'Speichern';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get copiedToClipboard => 'In Zwischenablage kopiert';

  @override
  String get waitForResponseToFinish => 'Warte, bis die Antwort fertig ist.';

  @override
  String get noImagesYet => 'Noch keine Bilder';

  @override
  String get tapGenerateHint =>
      'Tippe auf Generieren, um dein erstes Bild zu erstellen';

  @override
  String get generate => 'Generieren';

  @override
  String get generateImage => 'Bild generieren';

  @override
  String get describeImage => 'Beschreibe das gewünschte Bild...';

  @override
  String get yourImageWillAppear => 'Dein Bild erscheint hier';

  @override
  String get starting => 'Wird gestartet...';

  @override
  String generatingPercent(int percent) {
    return 'Generiert $percent%';
  }

  @override
  String get generateAnother => 'Weiteres generieren';

  @override
  String get generationFailed => 'Generierung fehlgeschlagen';

  @override
  String get trending => 'Trends';

  @override
  String get recent => 'Aktuell';

  @override
  String get nothingToDiscover => 'Noch nichts zu entdecken';

  @override
  String get freePlan => 'Kostenloser Tarif';

  @override
  String get premiumPlan => 'Premium-Tarif';

  @override
  String get proPlan => 'Pro-Tarif';

  @override
  String get proMaxPlan => 'Pro Max-Tarif';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get upgradeHint => 'Upgrade für mehr Tokens und Modelle';

  @override
  String get tokenUsage => 'Token-Nutzung';

  @override
  String get used => 'verwendet';

  @override
  String get limit => 'Limit';

  @override
  String get settings => 'Einstellungen';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get changePassword => 'Passwort ändern';

  @override
  String get language => 'Sprache';

  @override
  String get account => 'Konto';

  @override
  String get editProfile => 'Profil bearbeiten';

  @override
  String get activeSessions => 'Aktive Sitzungen';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountConfirm =>
      'Konto dauerhaft löschen? Dies kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAccountPasswordOptional =>
      'Leer lassen, wenn du dich mit Google oder Apple angemeldet hast.';

  @override
  String get signOutQuestion => 'Abmelden?';

  @override
  String get signOutBody => 'Du musst dich erneut anmelden.';

  @override
  String get voiceInput => 'Spracheingabe';

  @override
  String get voiceInputHint => 'Halten zum Aufnehmen, loslassen zum Senden.';

  @override
  String get voiceTranscribing => 'Wird transkribiert…';

  @override
  String get voicePermissionDenied => 'Mikrofonzugriff verweigert.';

  @override
  String get attach => 'Anhängen';

  @override
  String get takePhoto => 'Foto aufnehmen';

  @override
  String get fromLibrary => 'Aus Galerie';

  @override
  String get uploadingFile => 'Wird hochgeladen…';

  @override
  String get shareChat => 'Chat teilen';

  @override
  String get visibility => 'Sichtbarkeit';

  @override
  String get visibilityPrivate => 'Privat';

  @override
  String get visibilityShared => 'Mit bestimmten Personen geteilt';

  @override
  String get visibilityPublic => 'Öffentlicher Link';

  @override
  String get shareWithEmail => 'Mit jemandem teilen (E-Mail)';

  @override
  String get addPerson => 'Hinzufügen';

  @override
  String get copyLink => 'Link kopieren';

  @override
  String get linkCopied => 'Link kopiert';

  @override
  String get errorGeneric =>
      'Etwas ist schiefgelaufen. Bitte erneut versuchen.';

  @override
  String get errorNetwork => 'Keine Internetverbindung.';

  @override
  String get errorSessionExpired =>
      'Sitzung abgelaufen. Bitte erneut anmelden.';

  @override
  String errorRateLimited(int seconds) {
    return 'Zu viele Anfragen. Versuch es in $seconds s erneut.';
  }

  @override
  String get errorQuotaExceeded => 'Token-Kontingent überschritten.';

  @override
  String get errorServer => 'Serverfehler. Bitte später erneut versuchen.';

  @override
  String get couldNotOpenBrowser => 'Browser konnte nicht geöffnet werden.';

  @override
  String get comingSoon => 'Demnächst verfügbar';

  @override
  String get newChat => 'Neuer Chat';

  @override
  String get media => 'Medien';

  @override
  String get research => 'Recherche';

  @override
  String get recents => 'Zuletzt';

  @override
  String get chatsWillAppearHere => 'Ihre Chats erscheinen hier';

  @override
  String get billing => 'Abrechnung';

  @override
  String get usageLabel => 'Verwendung';

  @override
  String get customPrompts => 'Eigene Prompts';

  @override
  String get memory => 'Speicher';

  @override
  String get capabilities => 'Fähigkeiten';

  @override
  String get designLab => 'Design-Labor';

  @override
  String get skills => 'Fähigkeiten';

  @override
  String get tools => 'Werkzeuge';

  @override
  String get premiumRequired => 'Premium-Funktion — Upgrade zum Aktivieren';

  @override
  String get memoryEmptyTitle => 'Noch keine Erinnerungen';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova speichert hier wichtigen Kontext aus Ihren Chats.';

  @override
  String get memoryAtCapacity =>
      'Speicher voll — älteste Einträge werden ersetzt.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Speicher fast voll ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Zuletzt extrahiert $when';
  }

  @override
  String get categoryPreferences => 'Präferenzen';

  @override
  String get categoryFacts => 'Fakten';

  @override
  String get categoryProjects => 'Projekte';

  @override
  String get categoryPatterns => 'Muster';

  @override
  String get categoryContext => 'Kontext';

  @override
  String get researchAll => 'Alle';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'Exploit';

  @override
  String get researchBugBounty => 'Bug-Bounty';

  @override
  String get researchMalware => 'Malware';

  @override
  String get researchPentest => 'Pentest';

  @override
  String get newResearch => 'Neue Recherche';

  @override
  String get noResearchYet => 'Noch keine Recherchen';

  @override
  String get researchEmptyHint =>
      'Starten Sie eine neue Recherche zu CVEs, Exploits oder Bedrohungen.';

  @override
  String get sources => 'Quellen';

  @override
  String get close => 'Schließen';

  @override
  String get doneLabel => 'Fertig';

  @override
  String get projectsTitle => 'Projekte';

  @override
  String get freePlan2 => 'Kostenloser Tarif';

  @override
  String get greetingMorning => 'Guten Morgen';

  @override
  String get greetingAfternoon => 'Guten Tag';

  @override
  String get greetingEvening => 'Guten Abend';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'System';

  @override
  String get noConversations => 'Noch keine Unterhaltungen';

  @override
  String get promptBrainstorm => 'Ideen sammeln';

  @override
  String get promptExplain => 'Konzept erklären';

  @override
  String get promptCode => 'Hilf mir beim Coden';
}
