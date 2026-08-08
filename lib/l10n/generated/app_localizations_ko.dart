// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppL10nKo extends AppL10n {
  AppL10nKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => '로그인';

  @override
  String get signUp => '회원가입';

  @override
  String get signOut => '로그아웃';

  @override
  String get signInToContinue => '계속하려면 로그인하세요';

  @override
  String get createAccount => '계정 만들기';

  @override
  String get joinCyberNeurovaFree => 'CyberNeurova에 무료로 가입';

  @override
  String get email => '이메일';

  @override
  String get password => '비밀번호';

  @override
  String get nameOptional => '이름 (선택)';

  @override
  String get forgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get dontHaveAccount => '계정이 없으신가요? 가입하기';

  @override
  String get alreadyHaveAccount => '이미 계정이 있으신가요? 로그인';

  @override
  String get orDivider => '또는';

  @override
  String get continueWithGoogle => 'Google로 계속하기';

  @override
  String get continueWithApple => 'Apple로 계속하기';

  @override
  String get enterValidEmail => '유효한 이메일을 입력하세요';

  @override
  String get passwordTooShort => '비밀번호가 너무 짧습니다';

  @override
  String get passwordMin8 => '최소 8자 이상';

  @override
  String get enterYourPassword => '비밀번호를 입력하세요';

  @override
  String get resetPassword => '비밀번호 재설정';

  @override
  String get resetPasswordHint => '계정 이메일을 입력하시면 비밀번호 재설정 링크를 보내드립니다.';

  @override
  String get sendResetLink => '재설정 링크 보내기';

  @override
  String get backToSignIn => '로그인으로 돌아가기';

  @override
  String get checkYourEmail => '이메일을 확인하세요';

  @override
  String resetSentBody(String email) {
    return '$email의 계정이 있다면 재설정 링크가 전송되었습니다. 보이지 않는다면 스팸함을 확인하세요.';
  }

  @override
  String get verifyEmailTitle => '이메일을 확인하세요';

  @override
  String verifyEmailBody(String email) {
    return '$email로 인증 링크를 보냈습니다. 링크를 눌러 계정을 활성화한 후 로그인하세요.';
  }

  @override
  String get ok => '확인';

  @override
  String get chats => '채팅';

  @override
  String get images => '이미지';

  @override
  String get discover => '둘러보기';

  @override
  String get profile => '프로필';

  @override
  String get noChatsYet => '아직 대화가 없습니다';

  @override
  String get startChattingHint => 'CyberNeurova AI와 대화를 시작하세요';

  @override
  String get newConversation => '새 대화';

  @override
  String get messageInputHint => 'CyberNeurova에 메시지...';

  @override
  String get howCanIHelp => '오늘 무엇을 도와드릴까요?';

  @override
  String get search => '검색';

  @override
  String get searchChatsHint => '채팅 검색…';

  @override
  String get typeToSearchChats => '채팅을 검색하려면 입력하세요';

  @override
  String noChatsMatch(String query) {
    return '\"$query\"와 일치하는 채팅이 없습니다';
  }

  @override
  String get rename => '이름 변경';

  @override
  String get deleteChat => '채팅 삭제';

  @override
  String get deleteChatQuestion => '채팅을 삭제할까요?';

  @override
  String get cannotBeUndone => '이 작업은 취소할 수 없습니다.';

  @override
  String get cancel => '취소';

  @override
  String get delete => '삭제';

  @override
  String get save => '저장';

  @override
  String get retry => '다시 시도';

  @override
  String get copiedToClipboard => '클립보드에 복사됨';

  @override
  String get waitForResponseToFinish => '응답이 끝날 때까지 기다리세요.';

  @override
  String get noImagesYet => '아직 이미지가 없습니다';

  @override
  String get tapGenerateHint => '생성을 눌러 첫 이미지를 만들어 보세요';

  @override
  String get generate => '생성';

  @override
  String get generateImage => '이미지 생성';

  @override
  String get describeImage => '원하는 이미지를 설명하세요...';

  @override
  String get yourImageWillAppear => '이미지가 여기에 표시됩니다';

  @override
  String get starting => '시작 중...';

  @override
  String generatingPercent(int percent) {
    return '생성 중 $percent%';
  }

  @override
  String get generateAnother => '다시 생성';

  @override
  String get generationFailed => '생성 실패';

  @override
  String get trending => '인기';

  @override
  String get recent => '최근';

  @override
  String get nothingToDiscover => '아직 둘러볼 콘텐츠가 없습니다';

  @override
  String get freePlan => '무료 플랜';

  @override
  String get premiumPlan => '프리미엄 플랜';

  @override
  String get proPlan => '프로 플랜';

  @override
  String get proMaxPlan => '프로 맥스 플랜';

  @override
  String get upgrade => '업그레이드';

  @override
  String get upgradeHint => '더 많은 토큰과 모델을 위해 업그레이드';

  @override
  String get tokenUsage => '토큰 사용량';

  @override
  String get used => '사용됨';

  @override
  String get limit => '한도';

  @override
  String get settings => '설정';

  @override
  String get notifications => '알림';

  @override
  String get changePassword => '비밀번호 변경';

  @override
  String get language => '언어';

  @override
  String get account => '계정';

  @override
  String get editProfile => '프로필 편집';

  @override
  String get activeSessions => '활성 세션';

  @override
  String get deleteAccount => '계정 삭제';

  @override
  String get deleteAccountConfirm => '계정을 영구적으로 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.';

  @override
  String get deleteAccountPasswordOptional =>
      'Google 또는 Apple로 로그인한 경우 비워 두세요.';

  @override
  String get signOutQuestion => '로그아웃 하시겠습니까?';

  @override
  String get signOutBody => '다시 로그인해야 합니다.';

  @override
  String get voiceInput => '음성 입력';

  @override
  String get voiceInputHint => '길게 눌러 녹음, 떼면 전송됩니다.';

  @override
  String get voiceTranscribing => '변환 중…';

  @override
  String get voicePermissionDenied => '마이크 권한이 거부되었습니다.';

  @override
  String get attach => '첨부';

  @override
  String get takePhoto => '사진 찍기';

  @override
  String get fromLibrary => '라이브러리에서';

  @override
  String get uploadingFile => '업로드 중…';

  @override
  String get shareChat => '채팅 공유';

  @override
  String get visibility => '공개 범위';

  @override
  String get visibilityPrivate => '비공개';

  @override
  String get visibilityShared => '특정 사용자와 공유';

  @override
  String get visibilityPublic => '공개 링크';

  @override
  String get shareWithEmail => '다른 사람과 공유 (이메일)';

  @override
  String get addPerson => '추가';

  @override
  String get copyLink => '링크 복사';

  @override
  String get linkCopied => '링크가 복사됨';

  @override
  String get errorGeneric => '문제가 발생했습니다. 다시 시도하세요.';

  @override
  String get errorNetwork => '인터넷 연결이 없습니다.';

  @override
  String get errorSessionExpired => '세션이 만료되었습니다. 다시 로그인하세요.';

  @override
  String errorRateLimited(int seconds) {
    return '요청이 너무 많습니다. $seconds초 후에 다시 시도하세요.';
  }

  @override
  String get errorQuotaExceeded => '토큰 할당량을 초과했습니다.';

  @override
  String get errorServer => '서버 오류입니다. 나중에 다시 시도하세요.';

  @override
  String get couldNotOpenBrowser => '브라우저를 열 수 없습니다.';

  @override
  String get comingSoon => '곧 출시';

  @override
  String get newChat => '새 채팅';

  @override
  String get media => '미디어';

  @override
  String get research => '리서치';

  @override
  String get recents => '최근 항목';

  @override
  String get chatsWillAppearHere => '채팅이 여기에 표시됩니다';

  @override
  String get billing => '결제';

  @override
  String get usageLabel => '사용량';

  @override
  String get customPrompts => '맞춤 프롬프트';

  @override
  String get memory => '메모리';

  @override
  String get capabilities => '기능';

  @override
  String get designLab => '디자인 랩';

  @override
  String get skills => '스킬';

  @override
  String get tools => '도구';

  @override
  String get premiumRequired => '프리미엄 기능 — 업그레이드하여 활성화';

  @override
  String get memoryEmptyTitle => '아직 메모리가 없습니다';

  @override
  String get memoryEmptyHint => 'CyberNeurova가 채팅의 중요한 맥락을 여기에 저장합니다.';

  @override
  String get memoryAtCapacity => '메모리가 가득 찼습니다 — 가장 오래된 항목부터 교체됩니다.';

  @override
  String memoryCapacityWarning(int percent) {
    return '메모리가 거의 찼습니다 ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return '마지막 추출 $when';
  }

  @override
  String get categoryPreferences => '선호도';

  @override
  String get categoryFacts => '사실';

  @override
  String get categoryProjects => '프로젝트';

  @override
  String get categoryPatterns => '패턴';

  @override
  String get categoryContext => '컨텍스트';

  @override
  String get researchAll => '전체';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => '익스플로잇';

  @override
  String get researchBugBounty => '버그 바운티';

  @override
  String get researchMalware => '악성코드';

  @override
  String get researchPentest => '모의해킹';

  @override
  String get newResearch => '새 리서치';

  @override
  String get noResearchYet => '리서치 세션이 없습니다';

  @override
  String get researchEmptyHint => 'CVE, 익스플로잇 또는 위협을 조사할 새 리서치를 시작하세요.';

  @override
  String get sources => '출처';

  @override
  String get close => '닫기';

  @override
  String get doneLabel => '완료';

  @override
  String get projectsTitle => '프로젝트';

  @override
  String get freePlan2 => '무료 요금제';

  @override
  String get greetingMorning => '좋은 아침';

  @override
  String get greetingAfternoon => '좋은 오후';

  @override
  String get greetingEvening => '좋은 저녁';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => '시스템';

  @override
  String get noConversations => '아직 대화가 없습니다';

  @override
  String get promptBrainstorm => '아이디어 브레인스토밍';

  @override
  String get promptExplain => '개념 설명';

  @override
  String get promptCode => '코딩 도와주세요';
}
