// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppL10nEs extends AppL10n {
  AppL10nEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signUp => 'Registrarse';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get signInToContinue => 'Inicia sesión para continuar';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get joinCyberNeurovaFree => 'Únete a CyberNeurova gratis';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get nameOptional => 'Nombre (opcional)';

  @override
  String get forgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get dontHaveAccount => '¿No tienes una cuenta? Regístrate';

  @override
  String get alreadyHaveAccount => '¿Ya tienes una cuenta? Inicia sesión';

  @override
  String get orDivider => 'O';

  @override
  String get continueWithGoogle => 'Continuar con Google';

  @override
  String get continueWithApple => 'Continuar con Apple';

  @override
  String get enterValidEmail => 'Introduce un correo válido';

  @override
  String get passwordTooShort => 'Contraseña demasiado corta';

  @override
  String get passwordMin8 => 'Al menos 8 caracteres';

  @override
  String get enterYourPassword => 'Introduce tu contraseña';

  @override
  String get resetPassword => 'Restablecer contraseña';

  @override
  String get resetPasswordHint =>
      'Introduce el correo de tu cuenta y te enviaremos un enlace para restablecer tu contraseña.';

  @override
  String get sendResetLink => 'Enviar enlace';

  @override
  String get backToSignIn => 'Volver al inicio de sesión';

  @override
  String get checkYourEmail => 'Revisa tu correo';

  @override
  String resetSentBody(String email) {
    return 'Si existe una cuenta para $email, te enviaremos un enlace de restablecimiento. Revisa la carpeta de spam si no lo ves.';
  }

  @override
  String get verifyEmailTitle => 'Revisa tu correo';

  @override
  String verifyEmailBody(String email) {
    return 'Enviamos un enlace de verificación a $email. Toca el enlace para activar tu cuenta y luego inicia sesión.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Chats';

  @override
  String get images => 'Imágenes';

  @override
  String get discover => 'Descubrir';

  @override
  String get profile => 'Perfil';

  @override
  String get noChatsYet => 'Aún no hay conversaciones';

  @override
  String get startChattingHint => 'Empieza a chatear con CyberNeurova AI';

  @override
  String get newConversation => 'Nueva conversación';

  @override
  String get messageInputHint => 'Mensaje a CyberNeurova...';

  @override
  String get howCanIHelp => '¿En qué puedo ayudarte hoy?';

  @override
  String get search => 'Buscar';

  @override
  String get searchChatsHint => 'Buscar chats…';

  @override
  String get typeToSearchChats => 'Escribe para buscar tus chats';

  @override
  String noChatsMatch(String query) {
    return 'Ningún chat coincide con \"$query\"';
  }

  @override
  String get rename => 'Renombrar';

  @override
  String get deleteChat => 'Eliminar chat';

  @override
  String get deleteChatQuestion => '¿Eliminar chat?';

  @override
  String get cannotBeUndone => 'Esto no se puede deshacer.';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get save => 'Guardar';

  @override
  String get retry => 'Reintentar';

  @override
  String get copiedToClipboard => 'Copiado al portapapeles';

  @override
  String get waitForResponseToFinish => 'Espera a que termine la respuesta.';

  @override
  String get noImagesYet => 'Aún no hay imágenes';

  @override
  String get tapGenerateHint => 'Toca Generar para crear tu primera imagen';

  @override
  String get generate => 'Generar';

  @override
  String get generateImage => 'Generar imagen';

  @override
  String get describeImage => 'Describe la imagen que quieres...';

  @override
  String get yourImageWillAppear => 'Tu imagen aparecerá aquí';

  @override
  String get starting => 'Iniciando...';

  @override
  String generatingPercent(int percent) {
    return 'Generando $percent%';
  }

  @override
  String get generateAnother => 'Generar otra';

  @override
  String get generationFailed => 'Error al generar';

  @override
  String get trending => 'Tendencias';

  @override
  String get recent => 'Recientes';

  @override
  String get nothingToDiscover => 'Aún no hay nada que descubrir';

  @override
  String get freePlan => 'Plan Gratis';

  @override
  String get premiumPlan => 'Plan Premium';

  @override
  String get proPlan => 'Plan Pro';

  @override
  String get proMaxPlan => 'Plan Pro Max';

  @override
  String get upgrade => 'Mejorar';

  @override
  String get upgradeHint => 'Mejora para más tokens y modelos';

  @override
  String get tokenUsage => 'Uso de tokens';

  @override
  String get used => 'usados';

  @override
  String get limit => 'límite';

  @override
  String get settings => 'Ajustes';

  @override
  String get notifications => 'Notificaciones';

  @override
  String get changePassword => 'Cambiar contraseña';

  @override
  String get language => 'Idioma';

  @override
  String get account => 'Cuenta';

  @override
  String get editProfile => 'Editar perfil';

  @override
  String get activeSessions => 'Sesiones activas';

  @override
  String get deleteAccount => 'Eliminar cuenta';

  @override
  String get deleteAccountConfirm =>
      '¿Eliminar tu cuenta permanentemente? Esto no se puede deshacer.';

  @override
  String get deleteAccountPasswordOptional =>
      'Déjalo en blanco si iniciaste sesión con Google o Apple.';

  @override
  String get signOutQuestion => '¿Cerrar sesión?';

  @override
  String get signOutBody => 'Tendrás que iniciar sesión de nuevo.';

  @override
  String get voiceInput => 'Entrada de voz';

  @override
  String get voiceInputHint =>
      'Mantén pulsado para grabar, suelta para enviar.';

  @override
  String get voiceTranscribing => 'Transcribiendo…';

  @override
  String get voicePermissionDenied => 'Permiso de micrófono denegado.';

  @override
  String get attach => 'Adjuntar';

  @override
  String get takePhoto => 'Hacer foto';

  @override
  String get fromLibrary => 'Desde la galería';

  @override
  String get uploadingFile => 'Subiendo…';

  @override
  String get shareChat => 'Compartir chat';

  @override
  String get visibility => 'Visibilidad';

  @override
  String get visibilityPrivate => 'Privado';

  @override
  String get visibilityShared => 'Compartido con personas específicas';

  @override
  String get visibilityPublic => 'Enlace público';

  @override
  String get shareWithEmail => 'Compartir con alguien (correo)';

  @override
  String get addPerson => 'Añadir';

  @override
  String get copyLink => 'Copiar enlace';

  @override
  String get linkCopied => 'Enlace copiado';

  @override
  String get errorGeneric => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get errorNetwork => 'Sin conexión a internet.';

  @override
  String get errorSessionExpired => 'Sesión expirada. Inicia sesión de nuevo.';

  @override
  String errorRateLimited(int seconds) {
    return 'Demasiadas solicitudes. Inténtalo en $seconds s.';
  }

  @override
  String get errorQuotaExceeded => 'Cuota de tokens superada.';

  @override
  String get errorServer => 'Error del servidor. Inténtalo más tarde.';

  @override
  String get couldNotOpenBrowser => 'No se pudo abrir el navegador.';

  @override
  String get comingSoon => 'Próximamente';

  @override
  String get newChat => 'Nuevo chat';

  @override
  String get media => 'Multimedia';

  @override
  String get research => 'Investigación';

  @override
  String get recents => 'Recientes';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => 'Tus chats aparecerán aquí';

  @override
  String get billing => 'Facturación';

  @override
  String get usageLabel => 'Uso';

  @override
  String get customPrompts => 'Indicaciones personalizadas';

  @override
  String get memory => 'Memoria';

  @override
  String get capabilities => 'Capacidades';

  @override
  String get designLab => 'Laboratorio de diseño';

  @override
  String get skills => 'Habilidades';

  @override
  String get tools => 'Herramientas';

  @override
  String get premiumRequired => 'Función Premium — mejora para habilitar';

  @override
  String get memoryEmptyTitle => 'Sin recuerdos aún';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova guardará aquí el contexto importante de tus chats.';

  @override
  String get memoryAtCapacity =>
      'Memoria llena — se reemplazarán las entradas más antiguas.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Memoria casi llena ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Última extracción $when';
  }

  @override
  String get categoryPreferences => 'Preferencias';

  @override
  String get categoryFacts => 'Hechos';

  @override
  String get categoryProjects => 'Proyectos';

  @override
  String get categoryPatterns => 'Patrones';

  @override
  String get categoryContext => 'Contexto';

  @override
  String get researchAll => 'Todo';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'Exploit';

  @override
  String get researchBugBounty => 'Bug bounty';

  @override
  String get researchMalware => 'Malware';

  @override
  String get researchPentest => 'Pentesting';

  @override
  String get newResearch => 'Nueva investigación';

  @override
  String get noResearchYet => 'Aún no hay investigaciones';

  @override
  String get researchEmptyHint =>
      'Inicia una nueva investigación sobre CVE, exploits o amenazas.';

  @override
  String get sources => 'Fuentes';

  @override
  String get close => 'Cerrar';

  @override
  String get doneLabel => 'Hecho';

  @override
  String get projectsTitle => 'Proyectos';

  @override
  String get freePlan2 => 'Plan gratuito';

  @override
  String get greetingMorning => 'Buenos días';

  @override
  String get greetingAfternoon => 'Buenas tardes';

  @override
  String get greetingEvening => 'Buenas noches';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Sistema';

  @override
  String get noConversations => 'Aún no hay conversaciones';

  @override
  String get promptBrainstorm => 'Generar ideas';

  @override
  String get promptExplain => 'Explica un concepto';

  @override
  String get promptCode => 'Ayúdame a programar';
}
