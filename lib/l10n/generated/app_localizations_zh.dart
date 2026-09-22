// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppL10nZh extends AppL10n {
  AppL10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => '登录';

  @override
  String get signUp => '注册';

  @override
  String get signOut => '退出登录';

  @override
  String get signInToContinue => '登录以继续';

  @override
  String get createAccount => '创建账户';

  @override
  String get joinCyberNeurovaFree => '免费加入 CyberNeurova';

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get nameOptional => '姓名（可选）';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get dontHaveAccount => '还没有账户？去注册';

  @override
  String get alreadyHaveAccount => '已有账户？去登录';

  @override
  String get orDivider => '或';

  @override
  String get continueWithGoogle => '使用 Google 继续';

  @override
  String get continueWithApple => '使用 Apple 继续';

  @override
  String get enterValidEmail => '请输入有效邮箱';

  @override
  String get passwordTooShort => '密码过短';

  @override
  String get passwordMin8 => '至少 8 个字符';

  @override
  String get enterYourPassword => '请输入密码';

  @override
  String get resetPassword => '重置密码';

  @override
  String get resetPasswordHint => '输入您账户的邮箱，我们将向您发送重置密码的链接。';

  @override
  String get sendResetLink => '发送重置链接';

  @override
  String get backToSignIn => '返回登录';

  @override
  String get checkYourEmail => '请查收邮件';

  @override
  String resetSentBody(String email) {
    return '如果 $email 存在账户，重置链接已发送。如果没看到，请检查垃圾邮件文件夹。';
  }

  @override
  String get verifyEmailTitle => '请查收邮件';

  @override
  String verifyEmailBody(String email) {
    return '我们已向 $email 发送了验证链接。点击链接以激活您的账户，然后登录。';
  }

  @override
  String get ok => '确定';

  @override
  String get chats => '聊天';

  @override
  String get images => '图片';

  @override
  String get discover => '发现';

  @override
  String get profile => '个人资料';

  @override
  String get noChatsYet => '暂无对话';

  @override
  String get startChattingHint => '开始与 CyberNeurova AI 聊天';

  @override
  String get newConversation => '新对话';

  @override
  String get messageInputHint => '向 CyberNeurova 发送消息...';

  @override
  String get howCanIHelp => '今天我能帮您什么？';

  @override
  String get search => '搜索';

  @override
  String get searchChatsHint => '搜索聊天…';

  @override
  String get typeToSearchChats => '输入以搜索您的聊天';

  @override
  String noChatsMatch(String query) {
    return '没有匹配「$query」的聊天';
  }

  @override
  String get rename => '重命名';

  @override
  String get deleteChat => '删除聊天';

  @override
  String get deleteChatQuestion => '删除聊天？';

  @override
  String get cannotBeUndone => '此操作无法撤销。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get retry => '重试';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get waitForResponseToFinish => '请等待回复完成。';

  @override
  String get noImagesYet => '暂无图片';

  @override
  String get tapGenerateHint => '点击「生成」以创建您的第一张图片';

  @override
  String get generate => '生成';

  @override
  String get generateImage => '生成图片';

  @override
  String get describeImage => '描述您想要的图片...';

  @override
  String get yourImageWillAppear => '您的图片将显示在这里';

  @override
  String get starting => '正在启动...';

  @override
  String generatingPercent(int percent) {
    return '生成中 $percent%';
  }

  @override
  String get generateAnother => '再生成一张';

  @override
  String get generationFailed => '生成失败';

  @override
  String get trending => '热门';

  @override
  String get recent => '最近';

  @override
  String get nothingToDiscover => '暂无可发现内容';

  @override
  String get freePlan => '免费版';

  @override
  String get premiumPlan => '高级版';

  @override
  String get proPlan => '专业版';

  @override
  String get proMaxPlan => '专业 Max 版';

  @override
  String get upgrade => '升级';

  @override
  String get upgradeHint => '升级以获取更多 Token 和模型';

  @override
  String get tokenUsage => 'Token 使用量';

  @override
  String get used => '已用';

  @override
  String get limit => '上限';

  @override
  String get settings => '设置';

  @override
  String get notifications => '通知';

  @override
  String get changePassword => '修改密码';

  @override
  String get language => '语言';

  @override
  String get account => '账户';

  @override
  String get editProfile => '编辑个人资料';

  @override
  String get activeSessions => '活跃会话';

  @override
  String get deleteAccount => '删除账户';

  @override
  String get deleteAccountConfirm => '永久删除您的账户？此操作无法撤销。';

  @override
  String get deleteAccountPasswordOptional => '如果你使用 Google 或 Apple 登录，请留空。';

  @override
  String get signOutQuestion => '退出登录？';

  @override
  String get signOutBody => '您需要重新登录。';

  @override
  String get voiceInput => '语音输入';

  @override
  String get voiceInputHint => '按住录音，松开发送。';

  @override
  String get voiceTranscribing => '转录中…';

  @override
  String get voicePermissionDenied => '麦克风权限被拒绝。';

  @override
  String get attach => '附件';

  @override
  String get takePhoto => '拍照';

  @override
  String get fromLibrary => '从相册';

  @override
  String get uploadingFile => '上传中…';

  @override
  String get shareChat => '分享聊天';

  @override
  String get visibility => '可见性';

  @override
  String get visibilityPrivate => '私密';

  @override
  String get visibilityShared => '与特定人共享';

  @override
  String get visibilityPublic => '公开链接';

  @override
  String get shareWithEmail => '与他人分享（邮箱）';

  @override
  String get addPerson => '添加';

  @override
  String get copyLink => '复制链接';

  @override
  String get linkCopied => '链接已复制';

  @override
  String get errorGeneric => '出错了，请重试。';

  @override
  String get errorNetwork => '无网络连接。';

  @override
  String get errorSessionExpired => '会话已过期，请重新登录。';

  @override
  String errorRateLimited(int seconds) {
    return '请求过多，请在 $seconds 秒后重试。';
  }

  @override
  String get errorQuotaExceeded => 'Token 配额已用尽。';

  @override
  String get errorServer => '服务器错误，请稍后重试。';

  @override
  String get couldNotOpenBrowser => '无法打开浏览器。';

  @override
  String get comingSoon => '即将推出';

  @override
  String get newChat => '新对话';

  @override
  String get media => '媒体';

  @override
  String get research => '研究';

  @override
  String get recents => '最近';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => '您的对话将显示在这里';

  @override
  String get billing => '账单';

  @override
  String get usageLabel => '用量';

  @override
  String get customPrompts => '自定义提示词';

  @override
  String get memory => '记忆';

  @override
  String get capabilities => '能力';

  @override
  String get designLab => '设计实验室';

  @override
  String get skills => '技能';

  @override
  String get tools => '工具';

  @override
  String get premiumRequired => '高级功能 — 升级以启用';

  @override
  String get memoryEmptyTitle => '暂无记忆';

  @override
  String get memoryEmptyHint => 'CyberNeurova 将在此保存您对话中的重要上下文。';

  @override
  String get memoryAtCapacity => '记忆已满 — 最旧的条目将被替换。';

  @override
  String memoryCapacityWarning(int percent) {
    return '记忆即将满载 ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return '上次提取 $when';
  }

  @override
  String get categoryPreferences => '偏好';

  @override
  String get categoryFacts => '事实';

  @override
  String get categoryProjects => '项目';

  @override
  String get categoryPatterns => '模式';

  @override
  String get categoryContext => '上下文';

  @override
  String get researchAll => '全部';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => '漏洞利用';

  @override
  String get researchBugBounty => '漏洞赏金';

  @override
  String get researchMalware => '恶意软件';

  @override
  String get researchPentest => '渗透测试';

  @override
  String get newResearch => '新建研究';

  @override
  String get noResearchYet => '暂无研究记录';

  @override
  String get researchEmptyHint => '开始新研究,调查 CVE、漏洞或威胁。';

  @override
  String get sources => '来源';

  @override
  String get close => '关闭';

  @override
  String get doneLabel => '完成';

  @override
  String get projectsTitle => '项目';

  @override
  String get freePlan2 => '免费版';

  @override
  String get greetingMorning => '早上好';

  @override
  String get greetingAfternoon => '下午好';

  @override
  String get greetingEvening => '晚上好';

  @override
  String greetingWithName(String period, String name) {
    return '$period,$name';
  }

  @override
  String get system => '系统';

  @override
  String get noConversations => '暂无对话';

  @override
  String get promptBrainstorm => '头脑风暴';

  @override
  String get promptExplain => '解释一个概念';

  @override
  String get promptCode => '帮我写代码';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppL10nZhHans extends AppL10nZh {
  AppL10nZhHans() : super('zh_Hans');

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => '登录';

  @override
  String get signUp => '注册';

  @override
  String get signOut => '退出登录';

  @override
  String get signInToContinue => '登录以继续';

  @override
  String get createAccount => '创建账户';

  @override
  String get joinCyberNeurovaFree => '免费加入 CyberNeurova';

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get nameOptional => '姓名（可选）';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get dontHaveAccount => '还没有账户？去注册';

  @override
  String get alreadyHaveAccount => '已有账户？去登录';

  @override
  String get orDivider => '或';

  @override
  String get continueWithGoogle => '使用 Google 继续';

  @override
  String get continueWithApple => '使用 Apple 继续';

  @override
  String get enterValidEmail => '请输入有效邮箱';

  @override
  String get passwordTooShort => '密码过短';

  @override
  String get passwordMin8 => '至少 8 个字符';

  @override
  String get enterYourPassword => '请输入密码';

  @override
  String get resetPassword => '重置密码';

  @override
  String get resetPasswordHint => '输入您账户的邮箱，我们将向您发送重置密码的链接。';

  @override
  String get sendResetLink => '发送重置链接';

  @override
  String get backToSignIn => '返回登录';

  @override
  String get checkYourEmail => '请查收邮件';

  @override
  String resetSentBody(String email) {
    return '如果 $email 存在账户，重置链接已发送。如果没看到，请检查垃圾邮件文件夹。';
  }

  @override
  String get verifyEmailTitle => '请查收邮件';

  @override
  String verifyEmailBody(String email) {
    return '我们已向 $email 发送了验证链接。点击链接以激活您的账户，然后登录。';
  }

  @override
  String get ok => '确定';

  @override
  String get chats => '聊天';

  @override
  String get images => '图片';

  @override
  String get discover => '发现';

  @override
  String get profile => '个人资料';

  @override
  String get noChatsYet => '暂无对话';

  @override
  String get startChattingHint => '开始与 CyberNeurova AI 聊天';

  @override
  String get newConversation => '新对话';

  @override
  String get messageInputHint => '向 CyberNeurova 发送消息...';

  @override
  String get howCanIHelp => '今天我能帮您什么？';

  @override
  String get search => '搜索';

  @override
  String get searchChatsHint => '搜索聊天…';

  @override
  String get typeToSearchChats => '输入以搜索您的聊天';

  @override
  String noChatsMatch(String query) {
    return '没有匹配「$query」的聊天';
  }

  @override
  String get rename => '重命名';

  @override
  String get deleteChat => '删除聊天';

  @override
  String get deleteChatQuestion => '删除聊天？';

  @override
  String get cannotBeUndone => '此操作无法撤销。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get retry => '重试';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get waitForResponseToFinish => '请等待回复完成。';

  @override
  String get noImagesYet => '暂无图片';

  @override
  String get tapGenerateHint => '点击「生成」以创建您的第一张图片';

  @override
  String get generate => '生成';

  @override
  String get generateImage => '生成图片';

  @override
  String get describeImage => '描述您想要的图片...';

  @override
  String get yourImageWillAppear => '您的图片将显示在这里';

  @override
  String get starting => '正在启动...';

  @override
  String generatingPercent(int percent) {
    return '生成中 $percent%';
  }

  @override
  String get generateAnother => '再生成一张';

  @override
  String get generationFailed => '生成失败';

  @override
  String get trending => '热门';

  @override
  String get recent => '最近';

  @override
  String get nothingToDiscover => '暂无可发现内容';

  @override
  String get freePlan => '免费版';

  @override
  String get premiumPlan => '高级版';

  @override
  String get proPlan => '专业版';

  @override
  String get proMaxPlan => '专业 Max 版';

  @override
  String get upgrade => '升级';

  @override
  String get upgradeHint => '升级以获取更多 Token 和模型';

  @override
  String get tokenUsage => 'Token 使用量';

  @override
  String get used => '已用';

  @override
  String get limit => '上限';

  @override
  String get settings => '设置';

  @override
  String get notifications => '通知';

  @override
  String get changePassword => '修改密码';

  @override
  String get language => '语言';

  @override
  String get account => '账户';

  @override
  String get editProfile => '编辑个人资料';

  @override
  String get activeSessions => '活跃会话';

  @override
  String get deleteAccount => '删除账户';

  @override
  String get deleteAccountConfirm => '永久删除您的账户？此操作无法撤销。';

  @override
  String get deleteAccountPasswordOptional => '如果你使用 Google 或 Apple 登录，请留空。';

  @override
  String get signOutQuestion => '退出登录？';

  @override
  String get signOutBody => '您需要重新登录。';

  @override
  String get voiceInput => '语音输入';

  @override
  String get voiceInputHint => '按住录音，松开发送。';

  @override
  String get voiceTranscribing => '转录中…';

  @override
  String get voicePermissionDenied => '麦克风权限被拒绝。';

  @override
  String get attach => '附件';

  @override
  String get takePhoto => '拍照';

  @override
  String get fromLibrary => '从相册';

  @override
  String get uploadingFile => '上传中…';

  @override
  String get shareChat => '分享聊天';

  @override
  String get visibility => '可见性';

  @override
  String get visibilityPrivate => '私密';

  @override
  String get visibilityShared => '与特定人共享';

  @override
  String get visibilityPublic => '公开链接';

  @override
  String get shareWithEmail => '与他人分享（邮箱）';

  @override
  String get addPerson => '添加';

  @override
  String get copyLink => '复制链接';

  @override
  String get linkCopied => '链接已复制';

  @override
  String get errorGeneric => '出错了，请重试。';

  @override
  String get errorNetwork => '无网络连接。';

  @override
  String get errorSessionExpired => '会话已过期，请重新登录。';

  @override
  String errorRateLimited(int seconds) {
    return '请求过多，请在 $seconds 秒后重试。';
  }

  @override
  String get errorQuotaExceeded => 'Token 配额已用尽。';

  @override
  String get errorServer => '服务器错误，请稍后重试。';

  @override
  String get couldNotOpenBrowser => '无法打开浏览器。';

  @override
  String get comingSoon => '即将推出';

  @override
  String get newChat => '新对话';

  @override
  String get media => '媒体';

  @override
  String get research => '研究';

  @override
  String get recents => '最近';

  @override
  String get chatsWillAppearHere => '您的对话将显示在这里';

  @override
  String get billing => '账单';

  @override
  String get usageLabel => '用量';

  @override
  String get customPrompts => '自定义提示词';

  @override
  String get memory => '记忆';

  @override
  String get capabilities => '能力';

  @override
  String get designLab => '设计实验室';

  @override
  String get skills => '技能';

  @override
  String get tools => '工具';

  @override
  String get premiumRequired => '高级功能 — 升级以启用';

  @override
  String get memoryEmptyTitle => '暂无记忆';

  @override
  String get memoryEmptyHint => 'CyberNeurova 将在此保存您对话中的重要上下文。';

  @override
  String get memoryAtCapacity => '记忆已满 — 最旧的条目将被替换。';

  @override
  String memoryCapacityWarning(int percent) {
    return '记忆即将满载 ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return '上次提取 $when';
  }

  @override
  String get categoryPreferences => '偏好';

  @override
  String get categoryFacts => '事实';

  @override
  String get categoryProjects => '项目';

  @override
  String get categoryPatterns => '模式';

  @override
  String get categoryContext => '上下文';

  @override
  String get researchAll => '全部';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => '漏洞利用';

  @override
  String get researchBugBounty => '漏洞赏金';

  @override
  String get researchMalware => '恶意软件';

  @override
  String get researchPentest => '渗透测试';

  @override
  String get newResearch => '新建研究';

  @override
  String get noResearchYet => '暂无研究记录';

  @override
  String get researchEmptyHint => '开始新研究,调查 CVE、漏洞或威胁。';

  @override
  String get sources => '来源';

  @override
  String get close => '关闭';

  @override
  String get doneLabel => '完成';

  @override
  String get projectsTitle => '项目';

  @override
  String get freePlan2 => '免费版';

  @override
  String get greetingMorning => '早上好';

  @override
  String get greetingAfternoon => '下午好';

  @override
  String get greetingEvening => '晚上好';

  @override
  String greetingWithName(String period, String name) {
    return '$period,$name';
  }

  @override
  String get system => '系统';

  @override
  String get noConversations => '暂无对话';

  @override
  String get promptBrainstorm => '头脑风暴';

  @override
  String get promptExplain => '解释一个概念';

  @override
  String get promptCode => '帮我写代码';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppL10nZhHant extends AppL10nZh {
  AppL10nZhHant() : super('zh_Hant');

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => '登入';

  @override
  String get signUp => '註冊';

  @override
  String get signOut => '登出';

  @override
  String get signInToContinue => '登入以繼續';

  @override
  String get createAccount => '建立帳戶';

  @override
  String get joinCyberNeurovaFree => '免費加入 CyberNeurova';

  @override
  String get email => '電子郵件';

  @override
  String get password => '密碼';

  @override
  String get nameOptional => '姓名（選填）';

  @override
  String get forgotPassword => '忘記密碼？';

  @override
  String get dontHaveAccount => '還沒有帳戶？前往註冊';

  @override
  String get alreadyHaveAccount => '已有帳戶？前往登入';

  @override
  String get orDivider => '或';

  @override
  String get continueWithGoogle => '使用 Google 繼續';

  @override
  String get continueWithApple => '使用 Apple 繼續';

  @override
  String get enterValidEmail => '請輸入有效的電子郵件';

  @override
  String get passwordTooShort => '密碼過短';

  @override
  String get passwordMin8 => '至少 8 個字元';

  @override
  String get enterYourPassword => '請輸入密碼';

  @override
  String get resetPassword => '重設密碼';

  @override
  String get resetPasswordHint => '輸入您帳戶的電子郵件，我們將傳送重設密碼的連結給您。';

  @override
  String get sendResetLink => '傳送重設連結';

  @override
  String get backToSignIn => '返回登入';

  @override
  String get checkYourEmail => '請查看您的電子郵件';

  @override
  String resetSentBody(String email) {
    return '若 $email 有對應帳戶，重設連結已寄出。若未收到，請查看垃圾郵件資料夾。';
  }

  @override
  String get verifyEmailTitle => '請查看您的電子郵件';

  @override
  String verifyEmailBody(String email) {
    return '我們已將驗證連結傳送至 $email。點擊連結以啟用您的帳戶，然後登入。';
  }

  @override
  String get ok => '確定';

  @override
  String get chats => '聊天';

  @override
  String get images => '圖片';

  @override
  String get discover => '探索';

  @override
  String get profile => '個人檔案';

  @override
  String get noChatsYet => '尚無對話';

  @override
  String get startChattingHint => '開始與 CyberNeurova AI 聊天';

  @override
  String get newConversation => '新對話';

  @override
  String get messageInputHint => '傳訊息給 CyberNeurova...';

  @override
  String get howCanIHelp => '今天我能幫您什麼？';

  @override
  String get search => '搜尋';

  @override
  String get searchChatsHint => '搜尋聊天…';

  @override
  String get typeToSearchChats => '輸入以搜尋您的聊天';

  @override
  String noChatsMatch(String query) {
    return '沒有符合「$query」的聊天';
  }

  @override
  String get rename => '重新命名';

  @override
  String get deleteChat => '刪除聊天';

  @override
  String get deleteChatQuestion => '刪除聊天？';

  @override
  String get cannotBeUndone => '此動作無法復原。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '刪除';

  @override
  String get save => '儲存';

  @override
  String get retry => '重試';

  @override
  String get copiedToClipboard => '已複製到剪貼簿';

  @override
  String get waitForResponseToFinish => '請等待回覆完成。';

  @override
  String get noImagesYet => '尚無圖片';

  @override
  String get tapGenerateHint => '點擊「生成」以建立您的第一張圖片';

  @override
  String get generate => '生成';

  @override
  String get generateImage => '生成圖片';

  @override
  String get describeImage => '描述您想要的圖片...';

  @override
  String get yourImageWillAppear => '您的圖片將顯示於此';

  @override
  String get starting => '啟動中...';

  @override
  String generatingPercent(int percent) {
    return '生成中 $percent%';
  }

  @override
  String get generateAnother => '再生成一張';

  @override
  String get generationFailed => '生成失敗';

  @override
  String get trending => '熱門';

  @override
  String get recent => '最近';

  @override
  String get nothingToDiscover => '尚無可探索內容';

  @override
  String get freePlan => '免費方案';

  @override
  String get premiumPlan => '高級方案';

  @override
  String get proPlan => '專業方案';

  @override
  String get proMaxPlan => '專業 Max 方案';

  @override
  String get upgrade => '升級';

  @override
  String get upgradeHint => '升級以獲得更多 Token 和模型';

  @override
  String get tokenUsage => 'Token 用量';

  @override
  String get used => '已使用';

  @override
  String get limit => '上限';

  @override
  String get settings => '設定';

  @override
  String get notifications => '通知';

  @override
  String get changePassword => '變更密碼';

  @override
  String get language => '語言';

  @override
  String get account => '帳戶';

  @override
  String get editProfile => '編輯個人檔案';

  @override
  String get activeSessions => '使用中工作階段';

  @override
  String get deleteAccount => '刪除帳戶';

  @override
  String get deleteAccountConfirm => '永久刪除您的帳戶？此動作無法復原。';

  @override
  String get deleteAccountPasswordOptional => '如果你使用 Google 或 Apple 登入，請留空。';

  @override
  String get signOutQuestion => '登出？';

  @override
  String get signOutBody => '您需要重新登入。';

  @override
  String get voiceInput => '語音輸入';

  @override
  String get voiceInputHint => '按住錄音，放開傳送。';

  @override
  String get voiceTranscribing => '轉錄中…';

  @override
  String get voicePermissionDenied => '麥克風權限遭拒。';

  @override
  String get attach => '附件';

  @override
  String get takePhoto => '拍照';

  @override
  String get fromLibrary => '從相簿';

  @override
  String get uploadingFile => '上傳中…';

  @override
  String get shareChat => '分享聊天';

  @override
  String get visibility => '可見性';

  @override
  String get visibilityPrivate => '私人';

  @override
  String get visibilityShared => '與特定人士共享';

  @override
  String get visibilityPublic => '公開連結';

  @override
  String get shareWithEmail => '與他人分享（電子郵件）';

  @override
  String get addPerson => '新增';

  @override
  String get copyLink => '複製連結';

  @override
  String get linkCopied => '已複製連結';

  @override
  String get errorGeneric => '發生錯誤，請重試。';

  @override
  String get errorNetwork => '沒有網路連線。';

  @override
  String get errorSessionExpired => '工作階段已過期，請重新登入。';

  @override
  String errorRateLimited(int seconds) {
    return '請求過多，請在 $seconds 秒後重試。';
  }

  @override
  String get errorQuotaExceeded => 'Token 配額已用完。';

  @override
  String get errorServer => '伺服器錯誤，請稍後再試。';

  @override
  String get couldNotOpenBrowser => '無法開啟瀏覽器。';

  @override
  String get comingSoon => '即將推出';

  @override
  String get newChat => '新對話';

  @override
  String get media => '媒體';

  @override
  String get research => '研究';

  @override
  String get recents => '最近';

  @override
  String get chatsWillAppearHere => '您的對話將顯示在這裡';

  @override
  String get billing => '帳單';

  @override
  String get usageLabel => '用量';

  @override
  String get customPrompts => '自訂提示詞';

  @override
  String get memory => '記憶';

  @override
  String get capabilities => '能力';

  @override
  String get designLab => '設計實驗室';

  @override
  String get skills => '技能';

  @override
  String get tools => '工具';

  @override
  String get premiumRequired => '進階功能 — 升級以啟用';

  @override
  String get memoryEmptyTitle => '尚無記憶';

  @override
  String get memoryEmptyHint => 'CyberNeurova 將在此儲存您對話中的重要上下文。';

  @override
  String get memoryAtCapacity => '記憶已滿 — 最舊的項目將被替換。';

  @override
  String memoryCapacityWarning(int percent) {
    return '記憶即將滿載 ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return '上次擷取 $when';
  }

  @override
  String get categoryPreferences => '偏好';

  @override
  String get categoryFacts => '事實';

  @override
  String get categoryProjects => '專案';

  @override
  String get categoryPatterns => '模式';

  @override
  String get categoryContext => '上下文';

  @override
  String get researchAll => '全部';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => '漏洞利用';

  @override
  String get researchBugBounty => '漏洞賞金';

  @override
  String get researchMalware => '惡意軟體';

  @override
  String get researchPentest => '滲透測試';

  @override
  String get newResearch => '新建研究';

  @override
  String get noResearchYet => '尚無研究記錄';

  @override
  String get researchEmptyHint => '開始新研究,調查 CVE、漏洞或威脅。';

  @override
  String get sources => '來源';

  @override
  String get close => '關閉';

  @override
  String get doneLabel => '完成';

  @override
  String get projectsTitle => '專案';

  @override
  String get freePlan2 => '免費版';

  @override
  String get greetingMorning => '早安';

  @override
  String get greetingAfternoon => '午安';

  @override
  String get greetingEvening => '晚安';

  @override
  String greetingWithName(String period, String name) {
    return '$period,$name';
  }

  @override
  String get system => '系統';

  @override
  String get noConversations => '尚無對話';

  @override
  String get promptBrainstorm => '腦力激盪';

  @override
  String get promptExplain => '解釋一個概念';

  @override
  String get promptCode => '幫我寫程式';
}
