// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppL10nRu extends AppL10n {
  AppL10nRu([String locale = 'ru']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Войти';

  @override
  String get signUp => 'Регистрация';

  @override
  String get signOut => 'Выйти';

  @override
  String get signInToContinue => 'Войдите, чтобы продолжить';

  @override
  String get createAccount => 'Создать аккаунт';

  @override
  String get joinCyberNeurovaFree => 'Присоединяйтесь к CyberNeurova бесплатно';

  @override
  String get email => 'Эл. почта';

  @override
  String get password => 'Пароль';

  @override
  String get nameOptional => 'Имя (необязательно)';

  @override
  String get forgotPassword => 'Забыли пароль?';

  @override
  String get dontHaveAccount => 'Нет аккаунта? Зарегистрируйтесь';

  @override
  String get alreadyHaveAccount => 'Уже есть аккаунт? Войдите';

  @override
  String get orDivider => 'ИЛИ';

  @override
  String get continueWithGoogle => 'Продолжить с Google';

  @override
  String get continueWithApple => 'Продолжить с Apple';

  @override
  String get enterValidEmail => 'Введите корректный email';

  @override
  String get passwordTooShort => 'Пароль слишком короткий';

  @override
  String get passwordMin8 => 'Минимум 8 символов';

  @override
  String get enterYourPassword => 'Введите пароль';

  @override
  String get resetPassword => 'Сбросить пароль';

  @override
  String get resetPasswordHint =>
      'Введите email вашего аккаунта, и мы отправим вам ссылку для сброса пароля.';

  @override
  String get sendResetLink => 'Отправить ссылку';

  @override
  String get backToSignIn => 'Назад ко входу';

  @override
  String get checkYourEmail => 'Проверьте почту';

  @override
  String resetSentBody(String email) {
    return 'Если аккаунт для $email существует, ссылка для сброса уже отправлена. Проверьте папку «Спам», если не видите её.';
  }

  @override
  String get verifyEmailTitle => 'Проверьте почту';

  @override
  String verifyEmailBody(String email) {
    return 'Мы отправили ссылку подтверждения на $email. Нажмите на ссылку, чтобы активировать аккаунт, затем войдите.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Чаты';

  @override
  String get images => 'Изображения';

  @override
  String get discover => 'Обзор';

  @override
  String get profile => 'Профиль';

  @override
  String get noChatsYet => 'Чатов пока нет';

  @override
  String get startChattingHint => 'Начните общение с CyberNeurova AI';

  @override
  String get newConversation => 'Новый чат';

  @override
  String get messageInputHint => 'Сообщение для CyberNeurova...';

  @override
  String get howCanIHelp => 'Чем я могу помочь?';

  @override
  String get search => 'Поиск';

  @override
  String get searchChatsHint => 'Поиск по чатам…';

  @override
  String get typeToSearchChats => 'Введите запрос для поиска по чатам';

  @override
  String noChatsMatch(String query) {
    return 'Нет чатов по запросу «$query»';
  }

  @override
  String get rename => 'Переименовать';

  @override
  String get deleteChat => 'Удалить чат';

  @override
  String get deleteChatQuestion => 'Удалить чат?';

  @override
  String get cannotBeUndone => 'Это действие нельзя отменить.';

  @override
  String get cancel => 'Отмена';

  @override
  String get delete => 'Удалить';

  @override
  String get save => 'Сохранить';

  @override
  String get retry => 'Повторить';

  @override
  String get copiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get waitForResponseToFinish => 'Дождитесь окончания ответа.';

  @override
  String get noImagesYet => 'Изображений пока нет';

  @override
  String get tapGenerateHint =>
      'Нажмите «Сгенерировать», чтобы создать первое изображение';

  @override
  String get generate => 'Сгенерировать';

  @override
  String get generateImage => 'Создать изображение';

  @override
  String get describeImage => 'Опишите нужное изображение...';

  @override
  String get yourImageWillAppear => 'Ваше изображение появится здесь';

  @override
  String get starting => 'Запуск...';

  @override
  String generatingPercent(int percent) {
    return 'Генерация $percent%';
  }

  @override
  String get generateAnother => 'Создать ещё';

  @override
  String get generationFailed => 'Ошибка генерации';

  @override
  String get trending => 'В тренде';

  @override
  String get recent => 'Недавнее';

  @override
  String get nothingToDiscover => 'Пока нечего открыть';

  @override
  String get freePlan => 'Бесплатный план';

  @override
  String get premiumPlan => 'План Premium';

  @override
  String get proPlan => 'План Pro';

  @override
  String get proMaxPlan => 'План Pro Max';

  @override
  String get upgrade => 'Улучшить';

  @override
  String get upgradeHint => 'Улучшите для большего числа токенов и моделей';

  @override
  String get tokenUsage => 'Использование токенов';

  @override
  String get used => 'использовано';

  @override
  String get limit => 'лимит';

  @override
  String get settings => 'Настройки';

  @override
  String get notifications => 'Уведомления';

  @override
  String get changePassword => 'Сменить пароль';

  @override
  String get language => 'Язык';

  @override
  String get account => 'Аккаунт';

  @override
  String get editProfile => 'Редактировать профиль';

  @override
  String get activeSessions => 'Активные сеансы';

  @override
  String get deleteAccount => 'Удалить аккаунт';

  @override
  String get deleteAccountConfirm =>
      'Удалить аккаунт навсегда? Это действие нельзя отменить.';

  @override
  String get deleteAccountPasswordOptional =>
      'Оставьте пустым, если вы вошли через Google или Apple.';

  @override
  String get signOutQuestion => 'Выйти?';

  @override
  String get signOutBody => 'Вам нужно будет войти снова.';

  @override
  String get voiceInput => 'Голосовой ввод';

  @override
  String get voiceInputHint =>
      'Удерживайте для записи, отпустите для отправки.';

  @override
  String get voiceTranscribing => 'Распознавание…';

  @override
  String get voicePermissionDenied => 'Доступ к микрофону запрещён.';

  @override
  String get attach => 'Прикрепить';

  @override
  String get takePhoto => 'Сделать фото';

  @override
  String get fromLibrary => 'Из галереи';

  @override
  String get uploadingFile => 'Загрузка…';

  @override
  String get shareChat => 'Поделиться чатом';

  @override
  String get visibility => 'Видимость';

  @override
  String get visibilityPrivate => 'Личный';

  @override
  String get visibilityShared => 'Доступен определённым людям';

  @override
  String get visibilityPublic => 'Публичная ссылка';

  @override
  String get shareWithEmail => 'Поделиться с кем-либо (email)';

  @override
  String get addPerson => 'Добавить';

  @override
  String get copyLink => 'Копировать ссылку';

  @override
  String get linkCopied => 'Ссылка скопирована';

  @override
  String get errorGeneric => 'Что-то пошло не так. Попробуйте снова.';

  @override
  String get errorNetwork => 'Нет подключения к интернету.';

  @override
  String get errorSessionExpired => 'Сеанс истёк. Войдите снова.';

  @override
  String errorRateLimited(int seconds) {
    return 'Слишком много запросов. Повторите через $seconds с.';
  }

  @override
  String get errorQuotaExceeded => 'Квота токенов исчерпана.';

  @override
  String get errorServer => 'Ошибка сервера. Попробуйте позже.';

  @override
  String get couldNotOpenBrowser => 'Не удалось открыть браузер.';

  @override
  String get comingSoon => 'Скоро';

  @override
  String get newChat => 'Новый чат';

  @override
  String get media => 'Медиа';

  @override
  String get research => 'Исследование';

  @override
  String get recents => 'Недавние';

  @override
  String get chatsWillAppearHere => 'Ваши чаты появятся здесь';

  @override
  String get billing => 'Оплата';

  @override
  String get usageLabel => 'Использование';

  @override
  String get customPrompts => 'Свои промпты';

  @override
  String get memory => 'Память';

  @override
  String get capabilities => 'Возможности';

  @override
  String get designLab => 'Дизайн-лаборатория';

  @override
  String get skills => 'Навыки';

  @override
  String get tools => 'Инструменты';

  @override
  String get premiumRequired =>
      'Функция Premium — улучшите тариф для активации';

  @override
  String get memoryEmptyTitle => 'Пока нет воспоминаний';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova будет сохранять здесь важный контекст из ваших чатов.';

  @override
  String get memoryAtCapacity =>
      'Память заполнена — старые записи будут заменены.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Память почти заполнена ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Последнее извлечение $when';
  }

  @override
  String get categoryPreferences => 'Предпочтения';

  @override
  String get categoryFacts => 'Факты';

  @override
  String get categoryProjects => 'Проекты';

  @override
  String get categoryPatterns => 'Шаблоны';

  @override
  String get categoryContext => 'Контекст';

  @override
  String get researchAll => 'Все';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'Эксплойт';

  @override
  String get researchBugBounty => 'Bug bounty';

  @override
  String get researchMalware => 'Вредоносы';

  @override
  String get researchPentest => 'Пентест';

  @override
  String get newResearch => 'Новое исследование';

  @override
  String get noResearchYet => 'Исследований пока нет';

  @override
  String get researchEmptyHint =>
      'Начните новое исследование по CVE, эксплойтам или угрозам.';

  @override
  String get sources => 'Источники';

  @override
  String get close => 'Закрыть';

  @override
  String get doneLabel => 'Готово';

  @override
  String get projectsTitle => 'Проекты';

  @override
  String get freePlan2 => 'Бесплатный тариф';

  @override
  String get greetingMorning => 'Доброе утро';

  @override
  String get greetingAfternoon => 'Добрый день';

  @override
  String get greetingEvening => 'Добрый вечер';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Система';

  @override
  String get noConversations => 'Пока нет разговоров';

  @override
  String get promptBrainstorm => 'Идеи для мозгового штурма';

  @override
  String get promptExplain => 'Объясни концепцию';

  @override
  String get promptCode => 'Помоги мне с кодом';
}
