// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppL10nNl extends AppL10n {
  AppL10nNl([String locale = 'nl']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Inloggen';

  @override
  String get signUp => 'Registreren';

  @override
  String get signOut => 'Uitloggen';

  @override
  String get signInToContinue => 'Log in om door te gaan';

  @override
  String get createAccount => 'Account aanmaken';

  @override
  String get joinCyberNeurovaFree => 'Word gratis lid van CyberNeurova';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Wachtwoord';

  @override
  String get nameOptional => 'Naam (optioneel)';

  @override
  String get forgotPassword => 'Wachtwoord vergeten?';

  @override
  String get dontHaveAccount => 'Nog geen account? Registreer';

  @override
  String get alreadyHaveAccount => 'Al een account? Inloggen';

  @override
  String get orDivider => 'OF';

  @override
  String get continueWithGoogle => 'Doorgaan met Google';

  @override
  String get continueWithApple => 'Doorgaan met Apple';

  @override
  String get enterValidEmail => 'Voer een geldig e-mailadres in';

  @override
  String get passwordTooShort => 'Wachtwoord te kort';

  @override
  String get passwordMin8 => 'Minimaal 8 tekens';

  @override
  String get enterYourPassword => 'Voer je wachtwoord in';

  @override
  String get resetPassword => 'Wachtwoord resetten';

  @override
  String get resetPasswordHint =>
      'Voer het e-mailadres van je account in en we sturen je een link om je wachtwoord te resetten.';

  @override
  String get sendResetLink => 'Resetlink versturen';

  @override
  String get backToSignIn => 'Terug naar inloggen';

  @override
  String get checkYourEmail => 'Controleer je e-mail';

  @override
  String resetSentBody(String email) {
    return 'Als er een account bestaat voor $email, is er een resetlink onderweg. Controleer je spammap als je het niet ziet.';
  }

  @override
  String get verifyEmailTitle => 'Controleer je e-mail';

  @override
  String verifyEmailBody(String email) {
    return 'We hebben een verificatielink verzonden naar $email. Tik op de link om je account te activeren en log daarna in.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Chats';

  @override
  String get images => 'Afbeeldingen';

  @override
  String get discover => 'Ontdek';

  @override
  String get profile => 'Profiel';

  @override
  String get noChatsYet => 'Nog geen gesprekken';

  @override
  String get startChattingHint => 'Begin met chatten met CyberNeurova AI';

  @override
  String get newConversation => 'Nieuw gesprek';

  @override
  String get messageInputHint => 'Bericht aan CyberNeurova...';

  @override
  String get howCanIHelp => 'Hoe kan ik je vandaag helpen?';

  @override
  String get search => 'Zoeken';

  @override
  String get searchChatsHint => 'Chats zoeken…';

  @override
  String get typeToSearchChats => 'Typ om je chats te doorzoeken';

  @override
  String noChatsMatch(String query) {
    return 'Geen chats komen overeen met \"$query\"';
  }

  @override
  String get rename => 'Naam wijzigen';

  @override
  String get deleteChat => 'Chat verwijderen';

  @override
  String get deleteChatQuestion => 'Chat verwijderen?';

  @override
  String get cannotBeUndone => 'Dit kan niet ongedaan worden gemaakt.';

  @override
  String get cancel => 'Annuleren';

  @override
  String get delete => 'Verwijderen';

  @override
  String get save => 'Opslaan';

  @override
  String get retry => 'Opnieuw proberen';

  @override
  String get copiedToClipboard => 'Gekopieerd naar klembord';

  @override
  String get waitForResponseToFinish => 'Wacht tot het antwoord klaar is.';

  @override
  String get noImagesYet => 'Nog geen afbeeldingen';

  @override
  String get tapGenerateHint =>
      'Tik op Genereren om je eerste afbeelding te maken';

  @override
  String get generate => 'Genereren';

  @override
  String get generateImage => 'Afbeelding genereren';

  @override
  String get describeImage => 'Beschrijf de gewenste afbeelding...';

  @override
  String get yourImageWillAppear => 'Je afbeelding verschijnt hier';

  @override
  String get starting => 'Bezig met starten...';

  @override
  String generatingPercent(int percent) {
    return 'Genereren $percent%';
  }

  @override
  String get generateAnother => 'Nog één genereren';

  @override
  String get generationFailed => 'Genereren mislukt';

  @override
  String get trending => 'Trending';

  @override
  String get recent => 'Recent';

  @override
  String get nothingToDiscover => 'Nog niets om te ontdekken';

  @override
  String get freePlan => 'Gratis abonnement';

  @override
  String get premiumPlan => 'Premium-abonnement';

  @override
  String get proPlan => 'Pro-abonnement';

  @override
  String get proMaxPlan => 'Pro Max-abonnement';

  @override
  String get upgrade => 'Upgraden';

  @override
  String get upgradeHint => 'Upgrade voor meer tokens en modellen';

  @override
  String get tokenUsage => 'Tokengebruik';

  @override
  String get used => 'gebruikt';

  @override
  String get limit => 'limiet';

  @override
  String get settings => 'Instellingen';

  @override
  String get notifications => 'Meldingen';

  @override
  String get changePassword => 'Wachtwoord wijzigen';

  @override
  String get language => 'Taal';

  @override
  String get account => 'Account';

  @override
  String get editProfile => 'Profiel bewerken';

  @override
  String get activeSessions => 'Actieve sessies';

  @override
  String get deleteAccount => 'Account verwijderen';

  @override
  String get deleteAccountConfirm =>
      'Je account permanent verwijderen? Dit kan niet ongedaan worden gemaakt.';

  @override
  String get deleteAccountPasswordOptional =>
      'Laat leeg als je bent ingelogd met Google of Apple.';

  @override
  String get signOutQuestion => 'Uitloggen?';

  @override
  String get signOutBody => 'Je moet opnieuw inloggen.';

  @override
  String get voiceInput => 'Spraakinvoer';

  @override
  String get voiceInputHint =>
      'Houd ingedrukt om op te nemen, laat los om te verzenden.';

  @override
  String get voiceTranscribing => 'Bezig met transcriberen…';

  @override
  String get voicePermissionDenied => 'Microfoontoestemming geweigerd.';

  @override
  String get attach => 'Bijvoegen';

  @override
  String get takePhoto => 'Foto maken';

  @override
  String get fromLibrary => 'Uit galerij';

  @override
  String get uploadingFile => 'Uploaden…';

  @override
  String get shareChat => 'Chat delen';

  @override
  String get visibility => 'Zichtbaarheid';

  @override
  String get visibilityPrivate => 'Privé';

  @override
  String get visibilityShared => 'Gedeeld met specifieke personen';

  @override
  String get visibilityPublic => 'Openbare link';

  @override
  String get shareWithEmail => 'Delen met iemand (e-mail)';

  @override
  String get addPerson => 'Toevoegen';

  @override
  String get copyLink => 'Link kopiëren';

  @override
  String get linkCopied => 'Link gekopieerd';

  @override
  String get errorGeneric => 'Er is iets misgegaan. Probeer het opnieuw.';

  @override
  String get errorNetwork => 'Geen internetverbinding.';

  @override
  String get errorSessionExpired => 'Sessie verlopen. Log opnieuw in.';

  @override
  String errorRateLimited(int seconds) {
    return 'Te veel verzoeken. Probeer over $seconds s opnieuw.';
  }

  @override
  String get errorQuotaExceeded => 'Tokenquotum overschreden.';

  @override
  String get errorServer => 'Serverfout. Probeer het later opnieuw.';

  @override
  String get couldNotOpenBrowser => 'Kon browser niet openen.';

  @override
  String get comingSoon => 'Binnenkort beschikbaar';

  @override
  String get newChat => 'Nieuwe chat';

  @override
  String get media => 'Media';

  @override
  String get research => 'Onderzoek';

  @override
  String get recents => 'Recent';

  @override
  String get chatsWillAppearHere => 'Je chats verschijnen hier';

  @override
  String get billing => 'Facturering';

  @override
  String get usageLabel => 'Gebruik';

  @override
  String get customPrompts => 'Aangepaste prompts';

  @override
  String get memory => 'Geheugen';

  @override
  String get capabilities => 'Mogelijkheden';

  @override
  String get designLab => 'Design-lab';

  @override
  String get skills => 'Vaardigheden';

  @override
  String get tools => 'Hulpmiddelen';

  @override
  String get premiumRequired => 'Premium-functie — upgrade om in te schakelen';

  @override
  String get memoryEmptyTitle => 'Nog geen herinneringen';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova bewaart hier belangrijke context uit je chats.';

  @override
  String get memoryAtCapacity =>
      'Geheugen vol — oudste items worden vervangen.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Geheugen bijna vol ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Laatst opgehaald $when';
  }

  @override
  String get categoryPreferences => 'Voorkeuren';

  @override
  String get categoryFacts => 'Feiten';

  @override
  String get categoryProjects => 'Projecten';

  @override
  String get categoryPatterns => 'Patronen';

  @override
  String get categoryContext => 'Context';

  @override
  String get researchAll => 'Alles';

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
  String get newResearch => 'Nieuw onderzoek';

  @override
  String get noResearchYet => 'Nog geen onderzoek';

  @override
  String get researchEmptyHint =>
      'Start een nieuw onderzoek naar CVE\'s, exploits of dreigingen.';

  @override
  String get sources => 'Bronnen';

  @override
  String get close => 'Sluiten';

  @override
  String get doneLabel => 'Klaar';

  @override
  String get projectsTitle => 'Projecten';

  @override
  String get freePlan2 => 'Gratis abonnement';

  @override
  String get greetingMorning => 'Goedemorgen';

  @override
  String get greetingAfternoon => 'Goedemiddag';

  @override
  String get greetingEvening => 'Goedenavond';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Systeem';

  @override
  String get noConversations => 'Nog geen gesprekken';

  @override
  String get promptBrainstorm => 'Brainstorm ideeën';

  @override
  String get promptExplain => 'Leg een concept uit';

  @override
  String get promptCode => 'Help me met code';
}
