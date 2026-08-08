// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppL10nJa extends AppL10n {
  AppL10nJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'ログイン';

  @override
  String get signUp => '新規登録';

  @override
  String get signOut => 'ログアウト';

  @override
  String get signInToContinue => '続行するにはログインしてください';

  @override
  String get createAccount => 'アカウントを作成';

  @override
  String get joinCyberNeurovaFree => 'CyberNeurova に無料で参加';

  @override
  String get email => 'メール';

  @override
  String get password => 'パスワード';

  @override
  String get nameOptional => '名前（任意）';

  @override
  String get forgotPassword => 'パスワードをお忘れですか？';

  @override
  String get dontHaveAccount => 'アカウントをお持ちでない方はこちら';

  @override
  String get alreadyHaveAccount => 'すでにアカウントをお持ちですか？ログイン';

  @override
  String get orDivider => 'または';

  @override
  String get continueWithGoogle => 'Google で続行';

  @override
  String get continueWithApple => 'Apple で続行';

  @override
  String get enterValidEmail => '有効なメールアドレスを入力してください';

  @override
  String get passwordTooShort => 'パスワードが短すぎます';

  @override
  String get passwordMin8 => '8 文字以上';

  @override
  String get enterYourPassword => 'パスワードを入力';

  @override
  String get resetPassword => 'パスワードをリセット';

  @override
  String get resetPasswordHint => 'アカウントのメールアドレスを入力すると、パスワードリセット用のリンクをお送りします。';

  @override
  String get sendResetLink => 'リンクを送信';

  @override
  String get backToSignIn => 'ログインに戻る';

  @override
  String get checkYourEmail => 'メールをご確認ください';

  @override
  String resetSentBody(String email) {
    return '$email のアカウントが存在する場合、リセットリンクをお送りしました。見当たらない場合は迷惑メールフォルダをご確認ください。';
  }

  @override
  String get verifyEmailTitle => 'メールをご確認ください';

  @override
  String verifyEmailBody(String email) {
    return '$email に確認リンクを送信しました。リンクをタップしてアカウントを有効化し、ログインしてください。';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'チャット';

  @override
  String get images => '画像';

  @override
  String get discover => '発見';

  @override
  String get profile => 'プロフィール';

  @override
  String get noChatsYet => 'まだ会話がありません';

  @override
  String get startChattingHint => 'CyberNeurova AI とチャットを始めましょう';

  @override
  String get newConversation => '新しい会話';

  @override
  String get messageInputHint => 'CyberNeurova にメッセージ...';

  @override
  String get howCanIHelp => '今日は何をお手伝いしましょうか？';

  @override
  String get search => '検索';

  @override
  String get searchChatsHint => 'チャットを検索…';

  @override
  String get typeToSearchChats => '入力してチャットを検索';

  @override
  String noChatsMatch(String query) {
    return '「$query」に一致するチャットはありません';
  }

  @override
  String get rename => '名前を変更';

  @override
  String get deleteChat => 'チャットを削除';

  @override
  String get deleteChatQuestion => 'チャットを削除しますか？';

  @override
  String get cannotBeUndone => 'この操作は取り消せません。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get delete => '削除';

  @override
  String get save => '保存';

  @override
  String get retry => '再試行';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get waitForResponseToFinish => '応答が完了するのをお待ちください。';

  @override
  String get noImagesYet => 'まだ画像がありません';

  @override
  String get tapGenerateHint => '「生成」をタップして最初の画像を作成';

  @override
  String get generate => '生成';

  @override
  String get generateImage => '画像を生成';

  @override
  String get describeImage => '作成したい画像を説明してください...';

  @override
  String get yourImageWillAppear => '画像はここに表示されます';

  @override
  String get starting => '開始中...';

  @override
  String generatingPercent(int percent) {
    return '生成中 $percent%';
  }

  @override
  String get generateAnother => 'もう一度生成';

  @override
  String get generationFailed => '生成に失敗しました';

  @override
  String get trending => 'トレンド';

  @override
  String get recent => '最近';

  @override
  String get nothingToDiscover => 'まだ発見するものはありません';

  @override
  String get freePlan => '無料プラン';

  @override
  String get premiumPlan => 'Premium プラン';

  @override
  String get proPlan => 'Pro プラン';

  @override
  String get proMaxPlan => 'Pro Max プラン';

  @override
  String get upgrade => 'アップグレード';

  @override
  String get upgradeHint => 'アップグレードでトークンとモデルを追加';

  @override
  String get tokenUsage => 'トークン使用量';

  @override
  String get used => '使用済み';

  @override
  String get limit => '上限';

  @override
  String get settings => '設定';

  @override
  String get notifications => '通知';

  @override
  String get changePassword => 'パスワードを変更';

  @override
  String get language => '言語';

  @override
  String get account => 'アカウント';

  @override
  String get editProfile => 'プロフィールを編集';

  @override
  String get activeSessions => 'アクティブなセッション';

  @override
  String get deleteAccount => 'アカウントを削除';

  @override
  String get deleteAccountConfirm => 'アカウントを完全に削除しますか？この操作は取り消せません。';

  @override
  String get deleteAccountPasswordOptional =>
      'Google または Apple でサインインした場合は空欄のままにしてください。';

  @override
  String get signOutQuestion => 'ログアウトしますか？';

  @override
  String get signOutBody => '再度ログインが必要になります。';

  @override
  String get voiceInput => '音声入力';

  @override
  String get voiceInputHint => '長押しで録音、離して送信。';

  @override
  String get voiceTranscribing => '文字起こし中…';

  @override
  String get voicePermissionDenied => 'マイクの許可が拒否されました。';

  @override
  String get attach => '添付';

  @override
  String get takePhoto => '写真を撮る';

  @override
  String get fromLibrary => 'ライブラリから';

  @override
  String get uploadingFile => 'アップロード中…';

  @override
  String get shareChat => 'チャットを共有';

  @override
  String get visibility => '公開範囲';

  @override
  String get visibilityPrivate => '非公開';

  @override
  String get visibilityShared => '特定の人と共有';

  @override
  String get visibilityPublic => '公開リンク';

  @override
  String get shareWithEmail => 'メールで共有';

  @override
  String get addPerson => '追加';

  @override
  String get copyLink => 'リンクをコピー';

  @override
  String get linkCopied => 'リンクをコピーしました';

  @override
  String get errorGeneric => 'エラーが発生しました。もう一度お試しください。';

  @override
  String get errorNetwork => 'インターネット接続がありません。';

  @override
  String get errorSessionExpired => 'セッションが切れました。再度ログインしてください。';

  @override
  String errorRateLimited(int seconds) {
    return 'リクエストが多すぎます。$seconds 秒後にお試しください。';
  }

  @override
  String get errorQuotaExceeded => 'トークンの上限を超えました。';

  @override
  String get errorServer => 'サーバーエラーです。後でお試しください。';

  @override
  String get couldNotOpenBrowser => 'ブラウザを開けませんでした。';

  @override
  String get comingSoon => '近日公開';

  @override
  String get newChat => '新規チャット';

  @override
  String get media => 'メディア';

  @override
  String get research => 'リサーチ';

  @override
  String get recents => '最近';

  @override
  String get chatsWillAppearHere => 'チャットはここに表示されます';

  @override
  String get billing => '請求';

  @override
  String get usageLabel => '使用状況';

  @override
  String get customPrompts => 'カスタムプロンプト';

  @override
  String get memory => 'メモリ';

  @override
  String get capabilities => '機能';

  @override
  String get designLab => 'デザインラボ';

  @override
  String get skills => 'スキル';

  @override
  String get tools => 'ツール';

  @override
  String get premiumRequired => 'プレミアム機能 — アップグレードで有効化';

  @override
  String get memoryEmptyTitle => 'まだ記憶はありません';

  @override
  String get memoryEmptyHint => 'CyberNeurova はチャットの重要な文脈をここに保存します。';

  @override
  String get memoryAtCapacity => 'メモリが上限です — 最も古いエントリが置き換えられます。';

  @override
  String memoryCapacityWarning(int percent) {
    return 'メモリがほぼ満杯 ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return '最終抽出: $when';
  }

  @override
  String get categoryPreferences => '好み';

  @override
  String get categoryFacts => '事実';

  @override
  String get categoryProjects => 'プロジェクト';

  @override
  String get categoryPatterns => 'パターン';

  @override
  String get categoryContext => 'コンテキスト';

  @override
  String get researchAll => 'すべて';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'エクスプロイト';

  @override
  String get researchBugBounty => 'バグ報奨金';

  @override
  String get researchMalware => 'マルウェア';

  @override
  String get researchPentest => 'ペンテスト';

  @override
  String get newResearch => '新規リサーチ';

  @override
  String get noResearchYet => 'リサーチはまだありません';

  @override
  String get researchEmptyHint => '新しいリサーチを開始して、CVE、エクスプロイト、脅威を調査します。';

  @override
  String get sources => 'ソース';

  @override
  String get close => '閉じる';

  @override
  String get doneLabel => '完了';

  @override
  String get projectsTitle => 'プロジェクト';

  @override
  String get freePlan2 => '無料プラン';

  @override
  String get greetingMorning => 'おはようございます';

  @override
  String get greetingAfternoon => 'こんにちは';

  @override
  String get greetingEvening => 'こんばんは';

  @override
  String greetingWithName(String period, String name) {
    return '$period、$nameさん';
  }

  @override
  String get system => 'システム';

  @override
  String get noConversations => 'まだ会話がありません';

  @override
  String get promptBrainstorm => 'アイデアを出す';

  @override
  String get promptExplain => '概念を説明する';

  @override
  String get promptCode => 'コーディングを手伝って';
}
