// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppL10nPt extends AppL10n {
  AppL10nPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Entrar';

  @override
  String get signUp => 'Cadastrar';

  @override
  String get signOut => 'Sair';

  @override
  String get signInToContinue => 'Entre para continuar';

  @override
  String get createAccount => 'Criar conta';

  @override
  String get joinCyberNeurovaFree => 'Junte-se ao CyberNeurova de graça';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Senha';

  @override
  String get nameOptional => 'Nome (opcional)';

  @override
  String get forgotPassword => 'Esqueceu a senha?';

  @override
  String get dontHaveAccount => 'Não tem uma conta? Cadastre-se';

  @override
  String get alreadyHaveAccount => 'Já tem uma conta? Entre';

  @override
  String get orDivider => 'OU';

  @override
  String get continueWithGoogle => 'Continuar com o Google';

  @override
  String get continueWithApple => 'Continuar com a Apple';

  @override
  String get enterValidEmail => 'Digite um e-mail válido';

  @override
  String get passwordTooShort => 'Senha muito curta';

  @override
  String get passwordMin8 => 'Pelo menos 8 caracteres';

  @override
  String get enterYourPassword => 'Digite sua senha';

  @override
  String get resetPassword => 'Redefinir senha';

  @override
  String get resetPasswordHint =>
      'Digite o e-mail da sua conta e enviaremos um link para redefinir sua senha.';

  @override
  String get sendResetLink => 'Enviar link';

  @override
  String get backToSignIn => 'Voltar ao login';

  @override
  String get checkYourEmail => 'Verifique seu e-mail';

  @override
  String resetSentBody(String email) {
    return 'Se existir uma conta para $email, um link de redefinição está a caminho. Verifique a pasta de spam se não o vir.';
  }

  @override
  String get verifyEmailTitle => 'Verifique seu e-mail';

  @override
  String verifyEmailBody(String email) {
    return 'Enviamos um link de verificação para $email. Toque no link para ativar sua conta e depois entre.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Conversas';

  @override
  String get images => 'Imagens';

  @override
  String get discover => 'Descobrir';

  @override
  String get profile => 'Perfil';

  @override
  String get noChatsYet => 'Ainda não há conversas';

  @override
  String get startChattingHint => 'Comece a conversar com o CyberNeurova AI';

  @override
  String get newConversation => 'Nova conversa';

  @override
  String get messageInputHint => 'Mensagem para CyberNeurova...';

  @override
  String get howCanIHelp => 'Como posso ajudar hoje?';

  @override
  String get search => 'Buscar';

  @override
  String get searchChatsHint => 'Buscar conversas…';

  @override
  String get typeToSearchChats => 'Digite para buscar suas conversas';

  @override
  String noChatsMatch(String query) {
    return 'Nenhuma conversa corresponde a \"$query\"';
  }

  @override
  String get rename => 'Renomear';

  @override
  String get deleteChat => 'Excluir conversa';

  @override
  String get deleteChatQuestion => 'Excluir conversa?';

  @override
  String get cannotBeUndone => 'Isso não pode ser desfeito.';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Excluir';

  @override
  String get save => 'Salvar';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get copiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get waitForResponseToFinish => 'Aguarde a resposta terminar.';

  @override
  String get noImagesYet => 'Ainda não há imagens';

  @override
  String get tapGenerateHint => 'Toque em Gerar para criar sua primeira imagem';

  @override
  String get generate => 'Gerar';

  @override
  String get generateImage => 'Gerar imagem';

  @override
  String get describeImage => 'Descreva a imagem que você quer...';

  @override
  String get yourImageWillAppear => 'Sua imagem aparecerá aqui';

  @override
  String get starting => 'Iniciando...';

  @override
  String generatingPercent(int percent) {
    return 'Gerando $percent%';
  }

  @override
  String get generateAnother => 'Gerar outra';

  @override
  String get generationFailed => 'Falha na geração';

  @override
  String get trending => 'Em alta';

  @override
  String get recent => 'Recentes';

  @override
  String get nothingToDiscover => 'Nada para descobrir ainda';

  @override
  String get freePlan => 'Plano Gratuito';

  @override
  String get premiumPlan => 'Plano Premium';

  @override
  String get proPlan => 'Plano Pro';

  @override
  String get proMaxPlan => 'Plano Pro Max';

  @override
  String get upgrade => 'Atualizar';

  @override
  String get upgradeHint => 'Atualize para mais tokens e modelos';

  @override
  String get tokenUsage => 'Uso de tokens';

  @override
  String get used => 'usados';

  @override
  String get limit => 'limite';

  @override
  String get settings => 'Configurações';

  @override
  String get notifications => 'Notificações';

  @override
  String get changePassword => 'Alterar senha';

  @override
  String get language => 'Idioma';

  @override
  String get account => 'Conta';

  @override
  String get editProfile => 'Editar perfil';

  @override
  String get activeSessions => 'Sessões ativas';

  @override
  String get deleteAccount => 'Excluir conta';

  @override
  String get deleteAccountConfirm =>
      'Excluir sua conta permanentemente? Isso não pode ser desfeito.';

  @override
  String get deleteAccountPasswordOptional =>
      'Deixe em branco se você entrou com o Google ou a Apple.';

  @override
  String get signOutQuestion => 'Sair?';

  @override
  String get signOutBody => 'Você precisará entrar novamente.';

  @override
  String get voiceInput => 'Entrada por voz';

  @override
  String get voiceInputHint => 'Segure para gravar, solte para enviar.';

  @override
  String get voiceTranscribing => 'Transcrevendo…';

  @override
  String get voicePermissionDenied => 'Permissão de microfone negada.';

  @override
  String get attach => 'Anexar';

  @override
  String get takePhoto => 'Tirar foto';

  @override
  String get fromLibrary => 'Da galeria';

  @override
  String get uploadingFile => 'Enviando…';

  @override
  String get shareChat => 'Compartilhar conversa';

  @override
  String get visibility => 'Visibilidade';

  @override
  String get visibilityPrivate => 'Privada';

  @override
  String get visibilityShared => 'Compartilhada com pessoas específicas';

  @override
  String get visibilityPublic => 'Link público';

  @override
  String get shareWithEmail => 'Compartilhar com alguém (e-mail)';

  @override
  String get addPerson => 'Adicionar';

  @override
  String get copyLink => 'Copiar link';

  @override
  String get linkCopied => 'Link copiado';

  @override
  String get errorGeneric => 'Algo deu errado. Tente novamente.';

  @override
  String get errorNetwork => 'Sem conexão com a internet.';

  @override
  String get errorSessionExpired => 'Sessão expirada. Entre novamente.';

  @override
  String errorRateLimited(int seconds) {
    return 'Muitas solicitações. Tente novamente em $seconds s.';
  }

  @override
  String get errorQuotaExceeded => 'Cota de tokens excedida.';

  @override
  String get errorServer => 'Erro do servidor. Tente novamente mais tarde.';

  @override
  String get couldNotOpenBrowser => 'Não foi possível abrir o navegador.';

  @override
  String get comingSoon => 'Em breve';

  @override
  String get newChat => 'Novo chat';

  @override
  String get media => 'Mídia';

  @override
  String get research => 'Pesquisa';

  @override
  String get recents => 'Recentes';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => 'Seus chats aparecerão aqui';

  @override
  String get billing => 'Faturamento';

  @override
  String get usageLabel => 'Uso';

  @override
  String get customPrompts => 'Prompts personalizados';

  @override
  String get memory => 'Memória';

  @override
  String get capabilities => 'Recursos';

  @override
  String get designLab => 'Laboratório de design';

  @override
  String get skills => 'Habilidades';

  @override
  String get tools => 'Ferramentas';

  @override
  String get premiumRequired => 'Recurso Premium — faça upgrade para ativar';

  @override
  String get memoryEmptyTitle => 'Nenhuma memória ainda';

  @override
  String get memoryEmptyHint =>
      'O CyberNeurova salvará aqui o contexto importante dos seus chats.';

  @override
  String get memoryAtCapacity =>
      'Memória cheia — entradas mais antigas serão substituídas.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Memória quase cheia ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Última extração $when';
  }

  @override
  String get categoryPreferences => 'Preferências';

  @override
  String get categoryFacts => 'Fatos';

  @override
  String get categoryProjects => 'Projetos';

  @override
  String get categoryPatterns => 'Padrões';

  @override
  String get categoryContext => 'Contexto';

  @override
  String get researchAll => 'Tudo';

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
  String get newResearch => 'Nova pesquisa';

  @override
  String get noResearchYet => 'Nenhuma pesquisa ainda';

  @override
  String get researchEmptyHint =>
      'Inicie uma nova pesquisa sobre CVEs, exploits ou ameaças.';

  @override
  String get sources => 'Fontes';

  @override
  String get close => 'Fechar';

  @override
  String get doneLabel => 'Concluído';

  @override
  String get projectsTitle => 'Projetos';

  @override
  String get freePlan2 => 'Plano gratuito';

  @override
  String get greetingMorning => 'Bom dia';

  @override
  String get greetingAfternoon => 'Boa tarde';

  @override
  String get greetingEvening => 'Boa noite';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Sistema';

  @override
  String get noConversations => 'Nenhuma conversa ainda';

  @override
  String get promptBrainstorm => 'Gerar ideias';

  @override
  String get promptExplain => 'Explicar um conceito';

  @override
  String get promptCode => 'Ajude-me a programar';
}
