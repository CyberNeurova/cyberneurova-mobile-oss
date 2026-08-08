// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppL10nIt extends AppL10n {
  AppL10nIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Accedi';

  @override
  String get signUp => 'Registrati';

  @override
  String get signOut => 'Esci';

  @override
  String get signInToContinue => 'Accedi per continuare';

  @override
  String get createAccount => 'Crea account';

  @override
  String get joinCyberNeurovaFree => 'Unisciti a CyberNeurova gratis';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get nameOptional => 'Nome (facoltativo)';

  @override
  String get forgotPassword => 'Password dimenticata?';

  @override
  String get dontHaveAccount => 'Non hai un account? Registrati';

  @override
  String get alreadyHaveAccount => 'Hai già un account? Accedi';

  @override
  String get orDivider => 'O';

  @override
  String get continueWithGoogle => 'Continua con Google';

  @override
  String get continueWithApple => 'Continua con Apple';

  @override
  String get enterValidEmail => 'Inserisci un\'email valida';

  @override
  String get passwordTooShort => 'Password troppo corta';

  @override
  String get passwordMin8 => 'Almeno 8 caratteri';

  @override
  String get enterYourPassword => 'Inserisci la password';

  @override
  String get resetPassword => 'Reimposta password';

  @override
  String get resetPasswordHint =>
      'Inserisci l\'email del tuo account e ti invieremo un link per reimpostare la password.';

  @override
  String get sendResetLink => 'Invia link';

  @override
  String get backToSignIn => 'Torna all\'accesso';

  @override
  String get checkYourEmail => 'Controlla la tua email';

  @override
  String resetSentBody(String email) {
    return 'Se esiste un account per $email, un link di reimpostazione è in arrivo. Controlla la cartella spam se non lo vedi.';
  }

  @override
  String get verifyEmailTitle => 'Controlla la tua email';

  @override
  String verifyEmailBody(String email) {
    return 'Abbiamo inviato un link di verifica a $email. Tocca il link per attivare il tuo account, poi accedi.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Chat';

  @override
  String get images => 'Immagini';

  @override
  String get discover => 'Scopri';

  @override
  String get profile => 'Profilo';

  @override
  String get noChatsYet => 'Nessuna conversazione';

  @override
  String get startChattingHint => 'Inizia a chattare con CyberNeurova AI';

  @override
  String get newConversation => 'Nuova conversazione';

  @override
  String get messageInputHint => 'Messaggio a CyberNeurova...';

  @override
  String get howCanIHelp => 'Come posso aiutarti oggi?';

  @override
  String get search => 'Cerca';

  @override
  String get searchChatsHint => 'Cerca chat…';

  @override
  String get typeToSearchChats => 'Digita per cercare nelle chat';

  @override
  String noChatsMatch(String query) {
    return 'Nessuna chat per \"$query\"';
  }

  @override
  String get rename => 'Rinomina';

  @override
  String get deleteChat => 'Elimina chat';

  @override
  String get deleteChatQuestion => 'Eliminare la chat?';

  @override
  String get cannotBeUndone => 'Questa azione non può essere annullata.';

  @override
  String get cancel => 'Annulla';

  @override
  String get delete => 'Elimina';

  @override
  String get save => 'Salva';

  @override
  String get retry => 'Riprova';

  @override
  String get copiedToClipboard => 'Copiato negli appunti';

  @override
  String get waitForResponseToFinish => 'Attendi il termine della risposta.';

  @override
  String get noImagesYet => 'Nessuna immagine';

  @override
  String get tapGenerateHint => 'Tocca Genera per creare la tua prima immagine';

  @override
  String get generate => 'Genera';

  @override
  String get generateImage => 'Genera immagine';

  @override
  String get describeImage => 'Descrivi l\'immagine che vuoi...';

  @override
  String get yourImageWillAppear => 'La tua immagine apparirà qui';

  @override
  String get starting => 'Avvio...';

  @override
  String generatingPercent(int percent) {
    return 'Generazione $percent%';
  }

  @override
  String get generateAnother => 'Genera un\'altra';

  @override
  String get generationFailed => 'Generazione fallita';

  @override
  String get trending => 'Di tendenza';

  @override
  String get recent => 'Recenti';

  @override
  String get nothingToDiscover => 'Nulla da scoprire per ora';

  @override
  String get freePlan => 'Piano Gratuito';

  @override
  String get premiumPlan => 'Piano Premium';

  @override
  String get proPlan => 'Piano Pro';

  @override
  String get proMaxPlan => 'Piano Pro Max';

  @override
  String get upgrade => 'Aggiorna';

  @override
  String get upgradeHint => 'Aggiorna per più token e modelli';

  @override
  String get tokenUsage => 'Utilizzo token';

  @override
  String get used => 'usati';

  @override
  String get limit => 'limite';

  @override
  String get settings => 'Impostazioni';

  @override
  String get notifications => 'Notifiche';

  @override
  String get changePassword => 'Cambia password';

  @override
  String get language => 'Lingua';

  @override
  String get account => 'Account';

  @override
  String get editProfile => 'Modifica profilo';

  @override
  String get activeSessions => 'Sessioni attive';

  @override
  String get deleteAccount => 'Elimina account';

  @override
  String get deleteAccountConfirm =>
      'Eliminare l\'account in modo permanente? Questa azione non può essere annullata.';

  @override
  String get deleteAccountPasswordOptional =>
      'Lascia vuoto se hai effettuato l\'accesso con Google o Apple.';

  @override
  String get signOutQuestion => 'Disconnettersi?';

  @override
  String get signOutBody => 'Dovrai accedere di nuovo.';

  @override
  String get voiceInput => 'Input vocale';

  @override
  String get voiceInputHint =>
      'Tieni premuto per registrare, rilascia per inviare.';

  @override
  String get voiceTranscribing => 'Trascrizione…';

  @override
  String get voicePermissionDenied => 'Autorizzazione microfono negata.';

  @override
  String get attach => 'Allega';

  @override
  String get takePhoto => 'Scatta foto';

  @override
  String get fromLibrary => 'Dalla galleria';

  @override
  String get uploadingFile => 'Caricamento…';

  @override
  String get shareChat => 'Condividi chat';

  @override
  String get visibility => 'Visibilità';

  @override
  String get visibilityPrivate => 'Privata';

  @override
  String get visibilityShared => 'Condivisa con persone specifiche';

  @override
  String get visibilityPublic => 'Link pubblico';

  @override
  String get shareWithEmail => 'Condividi con qualcuno (email)';

  @override
  String get addPerson => 'Aggiungi';

  @override
  String get copyLink => 'Copia link';

  @override
  String get linkCopied => 'Link copiato';

  @override
  String get errorGeneric => 'Qualcosa è andato storto. Riprova.';

  @override
  String get errorNetwork => 'Nessuna connessione a internet.';

  @override
  String get errorSessionExpired => 'Sessione scaduta. Accedi di nuovo.';

  @override
  String errorRateLimited(int seconds) {
    return 'Troppe richieste. Riprova tra $seconds s.';
  }

  @override
  String get errorQuotaExceeded => 'Quota token superata.';

  @override
  String get errorServer => 'Errore del server. Riprova più tardi.';

  @override
  String get couldNotOpenBrowser => 'Impossibile aprire il browser.';

  @override
  String get comingSoon => 'In arrivo';

  @override
  String get newChat => 'Nuova chat';

  @override
  String get media => 'Media';

  @override
  String get research => 'Ricerca';

  @override
  String get recents => 'Recenti';

  @override
  String get chatsWillAppearHere => 'Le tue chat appariranno qui';

  @override
  String get billing => 'Fatturazione';

  @override
  String get usageLabel => 'Utilizzo';

  @override
  String get customPrompts => 'Prompt personalizzati';

  @override
  String get memory => 'Memoria';

  @override
  String get capabilities => 'Capacità';

  @override
  String get designLab => 'Laboratorio di design';

  @override
  String get skills => 'Competenze';

  @override
  String get tools => 'Strumenti';

  @override
  String get premiumRequired =>
      'Funzione Premium — esegui l\'upgrade per attivarla';

  @override
  String get memoryEmptyTitle => 'Ancora nessun ricordo';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova salverà qui il contesto importante delle tue chat.';

  @override
  String get memoryAtCapacity =>
      'Memoria piena — le voci più vecchie saranno sostituite.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Memoria quasi piena ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Ultima estrazione $when';
  }

  @override
  String get categoryPreferences => 'Preferenze';

  @override
  String get categoryFacts => 'Fatti';

  @override
  String get categoryProjects => 'Progetti';

  @override
  String get categoryPatterns => 'Schemi';

  @override
  String get categoryContext => 'Contesto';

  @override
  String get researchAll => 'Tutto';

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
  String get newResearch => 'Nuova ricerca';

  @override
  String get noResearchYet => 'Ancora nessuna ricerca';

  @override
  String get researchEmptyHint =>
      'Avvia una nuova ricerca su CVE, exploit o minacce.';

  @override
  String get sources => 'Fonti';

  @override
  String get close => 'Chiudi';

  @override
  String get doneLabel => 'Fatto';

  @override
  String get projectsTitle => 'Progetti';

  @override
  String get freePlan2 => 'Piano gratuito';

  @override
  String get greetingMorning => 'Buongiorno';

  @override
  String get greetingAfternoon => 'Buon pomeriggio';

  @override
  String get greetingEvening => 'Buonasera';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Sistema';

  @override
  String get noConversations => 'Ancora nessuna conversazione';

  @override
  String get promptBrainstorm => 'Genera idee';

  @override
  String get promptExplain => 'Spiega un concetto';

  @override
  String get promptCode => 'Aiutami a programmare';
}
