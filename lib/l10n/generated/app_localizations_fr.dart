// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppL10nFr extends AppL10n {
  AppL10nFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signUp => 'S\'inscrire';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signInToContinue => 'Connectez-vous pour continuer';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get joinCyberNeurovaFree => 'Rejoignez CyberNeurova gratuitement';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get nameOptional => 'Nom (facultatif)';

  @override
  String get forgotPassword => 'Mot de passe oublié ?';

  @override
  String get dontHaveAccount => 'Pas de compte ? Inscrivez-vous';

  @override
  String get alreadyHaveAccount => 'Déjà un compte ? Connectez-vous';

  @override
  String get orDivider => 'OU';

  @override
  String get continueWithGoogle => 'Continuer avec Google';

  @override
  String get continueWithApple => 'Continuer avec Apple';

  @override
  String get enterValidEmail => 'Entrez un e-mail valide';

  @override
  String get passwordTooShort => 'Mot de passe trop court';

  @override
  String get passwordMin8 => 'Au moins 8 caractères';

  @override
  String get enterYourPassword => 'Entrez votre mot de passe';

  @override
  String get resetPassword => 'Réinitialiser le mot de passe';

  @override
  String get resetPasswordHint =>
      'Entrez l\'e-mail de votre compte et nous vous enverrons un lien pour réinitialiser votre mot de passe.';

  @override
  String get sendResetLink => 'Envoyer le lien';

  @override
  String get backToSignIn => 'Retour à la connexion';

  @override
  String get checkYourEmail => 'Vérifiez votre e-mail';

  @override
  String resetSentBody(String email) {
    return 'Si un compte existe pour $email, un lien de réinitialisation est en route. Vérifiez vos spams si vous ne le voyez pas.';
  }

  @override
  String get verifyEmailTitle => 'Vérifiez votre e-mail';

  @override
  String verifyEmailBody(String email) {
    return 'Nous avons envoyé un lien de vérification à $email. Appuyez sur le lien pour activer votre compte, puis connectez-vous.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Discussions';

  @override
  String get images => 'Images';

  @override
  String get discover => 'Découvrir';

  @override
  String get profile => 'Profil';

  @override
  String get noChatsYet => 'Aucune conversation';

  @override
  String get startChattingHint => 'Commencez à discuter avec CyberNeurova AI';

  @override
  String get newConversation => 'Nouvelle conversation';

  @override
  String get messageInputHint => 'Message à CyberNeurova...';

  @override
  String get howCanIHelp => 'Comment puis-je vous aider ?';

  @override
  String get search => 'Rechercher';

  @override
  String get searchChatsHint => 'Rechercher des discussions…';

  @override
  String get typeToSearchChats => 'Tapez pour rechercher vos discussions';

  @override
  String noChatsMatch(String query) {
    return 'Aucune discussion ne correspond à « $query »';
  }

  @override
  String get rename => 'Renommer';

  @override
  String get deleteChat => 'Supprimer la discussion';

  @override
  String get deleteChatQuestion => 'Supprimer la discussion ?';

  @override
  String get cannotBeUndone => 'Cette action est irréversible.';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get save => 'Enregistrer';

  @override
  String get retry => 'Réessayer';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get waitForResponseToFinish => 'Attendez la fin de la réponse.';

  @override
  String get noImagesYet => 'Aucune image';

  @override
  String get tapGenerateHint =>
      'Appuyez sur Générer pour créer votre première image';

  @override
  String get generate => 'Générer';

  @override
  String get generateImage => 'Générer une image';

  @override
  String get describeImage => 'Décrivez l\'image souhaitée...';

  @override
  String get yourImageWillAppear => 'Votre image apparaîtra ici';

  @override
  String get starting => 'Démarrage...';

  @override
  String generatingPercent(int percent) {
    return 'Génération $percent%';
  }

  @override
  String get generateAnother => 'En générer une autre';

  @override
  String get generationFailed => 'Échec de la génération';

  @override
  String get trending => 'Tendances';

  @override
  String get recent => 'Récents';

  @override
  String get nothingToDiscover => 'Rien à découvrir pour l\'instant';

  @override
  String get freePlan => 'Forfait gratuit';

  @override
  String get premiumPlan => 'Forfait Premium';

  @override
  String get proPlan => 'Forfait Pro';

  @override
  String get proMaxPlan => 'Forfait Pro Max';

  @override
  String get upgrade => 'Mettre à niveau';

  @override
  String get upgradeHint => 'Mettez à niveau pour plus de tokens et de modèles';

  @override
  String get tokenUsage => 'Utilisation des tokens';

  @override
  String get used => 'utilisés';

  @override
  String get limit => 'limite';

  @override
  String get settings => 'Paramètres';

  @override
  String get notifications => 'Notifications';

  @override
  String get changePassword => 'Changer le mot de passe';

  @override
  String get language => 'Langue';

  @override
  String get account => 'Compte';

  @override
  String get editProfile => 'Modifier le profil';

  @override
  String get activeSessions => 'Sessions actives';

  @override
  String get deleteAccount => 'Supprimer le compte';

  @override
  String get deleteAccountConfirm =>
      'Supprimer définitivement votre compte ? Cette action est irréversible.';

  @override
  String get deleteAccountPasswordOptional =>
      'Laissez vide si vous vous êtes connecté avec Google ou Apple.';

  @override
  String get signOutQuestion => 'Se déconnecter ?';

  @override
  String get signOutBody => 'Vous devrez vous reconnecter.';

  @override
  String get voiceInput => 'Saisie vocale';

  @override
  String get voiceInputHint =>
      'Maintenez pour enregistrer, relâchez pour envoyer.';

  @override
  String get voiceTranscribing => 'Transcription…';

  @override
  String get voicePermissionDenied => 'Autorisation du microphone refusée.';

  @override
  String get attach => 'Joindre';

  @override
  String get takePhoto => 'Prendre une photo';

  @override
  String get fromLibrary => 'Depuis la galerie';

  @override
  String get uploadingFile => 'Envoi…';

  @override
  String get shareChat => 'Partager la discussion';

  @override
  String get visibility => 'Visibilité';

  @override
  String get visibilityPrivate => 'Privé';

  @override
  String get visibilityShared => 'Partagé avec des personnes spécifiques';

  @override
  String get visibilityPublic => 'Lien public';

  @override
  String get shareWithEmail => 'Partager avec quelqu\'un (e-mail)';

  @override
  String get addPerson => 'Ajouter';

  @override
  String get copyLink => 'Copier le lien';

  @override
  String get linkCopied => 'Lien copié';

  @override
  String get errorGeneric => 'Une erreur s\'est produite. Réessayez.';

  @override
  String get errorNetwork => 'Pas de connexion Internet.';

  @override
  String get errorSessionExpired => 'Session expirée. Reconnectez-vous.';

  @override
  String errorRateLimited(int seconds) {
    return 'Trop de requêtes. Réessayez dans $seconds s.';
  }

  @override
  String get errorQuotaExceeded => 'Quota de tokens dépassé.';

  @override
  String get errorServer => 'Erreur serveur. Réessayez plus tard.';

  @override
  String get couldNotOpenBrowser => 'Impossible d\'ouvrir le navigateur.';

  @override
  String get comingSoon => 'Bientôt disponible';

  @override
  String get newChat => 'Nouvelle discussion';

  @override
  String get media => 'Médias';

  @override
  String get research => 'Recherche';

  @override
  String get recents => 'Récents';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => 'Vos discussions apparaîtront ici';

  @override
  String get billing => 'Facturation';

  @override
  String get usageLabel => 'Utilisation';

  @override
  String get customPrompts => 'Invites personnalisées';

  @override
  String get memory => 'Mémoire';

  @override
  String get capabilities => 'Capacités';

  @override
  String get designLab => 'Laboratoire de design';

  @override
  String get skills => 'Compétences';

  @override
  String get tools => 'Outils';

  @override
  String get premiumRequired =>
      'Fonctionnalité Premium — mettez à niveau pour l\'activer';

  @override
  String get memoryEmptyTitle => 'Aucun souvenir pour l\'instant';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova enregistrera ici le contexte important de vos discussions.';

  @override
  String get memoryAtCapacity =>
      'Mémoire pleine — les plus anciennes entrées seront remplacées.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Mémoire presque pleine ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Dernière extraction $when';
  }

  @override
  String get categoryPreferences => 'Préférences';

  @override
  String get categoryFacts => 'Faits';

  @override
  String get categoryProjects => 'Projets';

  @override
  String get categoryPatterns => 'Motifs';

  @override
  String get categoryContext => 'Contexte';

  @override
  String get researchAll => 'Tout';

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
  String get newResearch => 'Nouvelle recherche';

  @override
  String get noResearchYet => 'Aucune recherche pour l\'instant';

  @override
  String get researchEmptyHint =>
      'Lancez une nouvelle recherche sur des CVE, exploits ou menaces.';

  @override
  String get sources => 'Sources';

  @override
  String get close => 'Fermer';

  @override
  String get doneLabel => 'Terminé';

  @override
  String get projectsTitle => 'Projets';

  @override
  String get freePlan2 => 'Forfait gratuit';

  @override
  String get greetingMorning => 'Bonjour';

  @override
  String get greetingAfternoon => 'Bon après-midi';

  @override
  String get greetingEvening => 'Bonsoir';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Système';

  @override
  String get noConversations => 'Aucune conversation pour l\'instant';

  @override
  String get promptBrainstorm => 'Trouver des idées';

  @override
  String get promptExplain => 'Expliquer un concept';

  @override
  String get promptCode => 'Aide-moi à coder';
}
