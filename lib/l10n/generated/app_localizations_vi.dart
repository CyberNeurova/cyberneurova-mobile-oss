// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppL10nVi extends AppL10n {
  AppL10nVi([String locale = 'vi']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Đăng nhập';

  @override
  String get signUp => 'Đăng ký';

  @override
  String get signOut => 'Đăng xuất';

  @override
  String get signInToContinue => 'Đăng nhập để tiếp tục';

  @override
  String get createAccount => 'Tạo tài khoản';

  @override
  String get joinCyberNeurovaFree => 'Tham gia CyberNeurova miễn phí';

  @override
  String get email => 'Email';

  @override
  String get password => 'Mật khẩu';

  @override
  String get nameOptional => 'Tên (tùy chọn)';

  @override
  String get forgotPassword => 'Quên mật khẩu?';

  @override
  String get dontHaveAccount => 'Chưa có tài khoản? Đăng ký';

  @override
  String get alreadyHaveAccount => 'Đã có tài khoản? Đăng nhập';

  @override
  String get orDivider => 'HOẶC';

  @override
  String get continueWithGoogle => 'Tiếp tục với Google';

  @override
  String get continueWithApple => 'Tiếp tục với Apple';

  @override
  String get enterValidEmail => 'Nhập email hợp lệ';

  @override
  String get passwordTooShort => 'Mật khẩu quá ngắn';

  @override
  String get passwordMin8 => 'Ít nhất 8 ký tự';

  @override
  String get enterYourPassword => 'Nhập mật khẩu';

  @override
  String get resetPassword => 'Đặt lại mật khẩu';

  @override
  String get resetPasswordHint =>
      'Nhập email tài khoản và chúng tôi sẽ gửi liên kết để đặt lại mật khẩu.';

  @override
  String get sendResetLink => 'Gửi liên kết';

  @override
  String get backToSignIn => 'Quay lại đăng nhập';

  @override
  String get checkYourEmail => 'Kiểm tra email của bạn';

  @override
  String resetSentBody(String email) {
    return 'Nếu có tài khoản cho $email, liên kết đặt lại đã được gửi. Kiểm tra thư mục spam nếu không thấy.';
  }

  @override
  String get verifyEmailTitle => 'Kiểm tra email của bạn';

  @override
  String verifyEmailBody(String email) {
    return 'Chúng tôi đã gửi liên kết xác minh đến $email. Nhấn vào liên kết để kích hoạt tài khoản, sau đó đăng nhập.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Trò chuyện';

  @override
  String get images => 'Hình ảnh';

  @override
  String get discover => 'Khám phá';

  @override
  String get profile => 'Hồ sơ';

  @override
  String get noChatsYet => 'Chưa có cuộc trò chuyện';

  @override
  String get startChattingHint => 'Bắt đầu trò chuyện với CyberNeurova AI';

  @override
  String get newConversation => 'Cuộc trò chuyện mới';

  @override
  String get messageInputHint => 'Nhắn tin cho CyberNeurova...';

  @override
  String get howCanIHelp => 'Hôm nay tôi có thể giúp gì?';

  @override
  String get search => 'Tìm kiếm';

  @override
  String get searchChatsHint => 'Tìm trong cuộc trò chuyện…';

  @override
  String get typeToSearchChats => 'Gõ để tìm trong các cuộc trò chuyện của bạn';

  @override
  String noChatsMatch(String query) {
    return 'Không có cuộc trò chuyện nào khớp với \"$query\"';
  }

  @override
  String get rename => 'Đổi tên';

  @override
  String get deleteChat => 'Xóa cuộc trò chuyện';

  @override
  String get deleteChatQuestion => 'Xóa cuộc trò chuyện?';

  @override
  String get cannotBeUndone => 'Hành động này không thể hoàn tác.';

  @override
  String get cancel => 'Hủy';

  @override
  String get delete => 'Xóa';

  @override
  String get save => 'Lưu';

  @override
  String get retry => 'Thử lại';

  @override
  String get copiedToClipboard => 'Đã sao chép vào bộ nhớ tạm';

  @override
  String get waitForResponseToFinish => 'Vui lòng đợi phản hồi hoàn tất.';

  @override
  String get noImagesYet => 'Chưa có hình ảnh';

  @override
  String get tapGenerateHint => 'Nhấn Tạo để tạo hình ảnh đầu tiên';

  @override
  String get generate => 'Tạo';

  @override
  String get generateImage => 'Tạo hình ảnh';

  @override
  String get describeImage => 'Mô tả hình ảnh bạn muốn...';

  @override
  String get yourImageWillAppear => 'Hình ảnh của bạn sẽ xuất hiện tại đây';

  @override
  String get starting => 'Đang bắt đầu...';

  @override
  String generatingPercent(int percent) {
    return 'Đang tạo $percent%';
  }

  @override
  String get generateAnother => 'Tạo cái khác';

  @override
  String get generationFailed => 'Tạo không thành công';

  @override
  String get trending => 'Thịnh hành';

  @override
  String get recent => 'Gần đây';

  @override
  String get nothingToDiscover => 'Chưa có gì để khám phá';

  @override
  String get freePlan => 'Gói miễn phí';

  @override
  String get premiumPlan => 'Gói Premium';

  @override
  String get proPlan => 'Gói Pro';

  @override
  String get proMaxPlan => 'Gói Pro Max';

  @override
  String get upgrade => 'Nâng cấp';

  @override
  String get upgradeHint => 'Nâng cấp để có thêm token và mô hình';

  @override
  String get tokenUsage => 'Sử dụng token';

  @override
  String get used => 'đã dùng';

  @override
  String get limit => 'giới hạn';

  @override
  String get settings => 'Cài đặt';

  @override
  String get notifications => 'Thông báo';

  @override
  String get changePassword => 'Đổi mật khẩu';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get account => 'Tài khoản';

  @override
  String get editProfile => 'Chỉnh sửa hồ sơ';

  @override
  String get activeSessions => 'Phiên đang hoạt động';

  @override
  String get deleteAccount => 'Xóa tài khoản';

  @override
  String get deleteAccountConfirm =>
      'Xóa vĩnh viễn tài khoản của bạn? Hành động này không thể hoàn tác.';

  @override
  String get deleteAccountPasswordOptional =>
      'Để trống nếu bạn đăng nhập bằng Google hoặc Apple.';

  @override
  String get signOutQuestion => 'Đăng xuất?';

  @override
  String get signOutBody => 'Bạn sẽ cần đăng nhập lại.';

  @override
  String get voiceInput => 'Nhập bằng giọng nói';

  @override
  String get voiceInputHint => 'Giữ để ghi âm, thả ra để gửi.';

  @override
  String get voiceTranscribing => 'Đang chuyển thành văn bản…';

  @override
  String get voicePermissionDenied => 'Quyền micro bị từ chối.';

  @override
  String get attach => 'Đính kèm';

  @override
  String get takePhoto => 'Chụp ảnh';

  @override
  String get fromLibrary => 'Từ thư viện';

  @override
  String get uploadingFile => 'Đang tải lên…';

  @override
  String get shareChat => 'Chia sẻ cuộc trò chuyện';

  @override
  String get visibility => 'Hiển thị';

  @override
  String get visibilityPrivate => 'Riêng tư';

  @override
  String get visibilityShared => 'Chia sẻ với người cụ thể';

  @override
  String get visibilityPublic => 'Liên kết công khai';

  @override
  String get shareWithEmail => 'Chia sẻ với ai đó (email)';

  @override
  String get addPerson => 'Thêm';

  @override
  String get copyLink => 'Sao chép liên kết';

  @override
  String get linkCopied => 'Đã sao chép liên kết';

  @override
  String get errorGeneric => 'Đã xảy ra lỗi. Vui lòng thử lại.';

  @override
  String get errorNetwork => 'Không có kết nối internet.';

  @override
  String get errorSessionExpired => 'Phiên đã hết hạn. Vui lòng đăng nhập lại.';

  @override
  String errorRateLimited(int seconds) {
    return 'Quá nhiều yêu cầu. Thử lại sau $seconds giây.';
  }

  @override
  String get errorQuotaExceeded => 'Đã vượt hạn ngạch token.';

  @override
  String get errorServer => 'Lỗi máy chủ. Thử lại sau.';

  @override
  String get couldNotOpenBrowser => 'Không thể mở trình duyệt.';

  @override
  String get comingSoon => 'Sắp ra mắt';

  @override
  String get newChat => 'Trò chuyện mới';

  @override
  String get media => 'Phương tiện';

  @override
  String get research => 'Nghiên cứu';

  @override
  String get recents => 'Gần đây';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => 'Cuộc trò chuyện của bạn sẽ hiện ở đây';

  @override
  String get billing => 'Thanh toán';

  @override
  String get usageLabel => 'Sử dụng';

  @override
  String get customPrompts => 'Lời nhắc tùy chỉnh';

  @override
  String get memory => 'Bộ nhớ';

  @override
  String get capabilities => 'Khả năng';

  @override
  String get designLab => 'Phòng thiết kế';

  @override
  String get skills => 'Kỹ năng';

  @override
  String get tools => 'Công cụ';

  @override
  String get premiumRequired => 'Tính năng Premium — nâng cấp để bật';

  @override
  String get memoryEmptyTitle => 'Chưa có bộ nhớ';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova sẽ lưu ngữ cảnh quan trọng từ các cuộc trò chuyện của bạn tại đây.';

  @override
  String get memoryAtCapacity => 'Bộ nhớ đầy — các mục cũ nhất sẽ bị thay thế.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Bộ nhớ sắp đầy ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Trích xuất gần nhất $when';
  }

  @override
  String get categoryPreferences => 'Tùy chọn';

  @override
  String get categoryFacts => 'Sự kiện';

  @override
  String get categoryProjects => 'Dự án';

  @override
  String get categoryPatterns => 'Mẫu';

  @override
  String get categoryContext => 'Ngữ cảnh';

  @override
  String get researchAll => 'Tất cả';

  @override
  String get researchCVE => 'CVE';

  @override
  String get researchExploit => 'Khai thác';

  @override
  String get researchBugBounty => 'Bug bounty';

  @override
  String get researchMalware => 'Mã độc';

  @override
  String get researchPentest => 'Pentest';

  @override
  String get newResearch => 'Nghiên cứu mới';

  @override
  String get noResearchYet => 'Chưa có nghiên cứu nào';

  @override
  String get researchEmptyHint =>
      'Bắt đầu nghiên cứu mới về CVE, lỗ hổng hoặc mối đe dọa.';

  @override
  String get sources => 'Nguồn';

  @override
  String get close => 'Đóng';

  @override
  String get doneLabel => 'Xong';

  @override
  String get projectsTitle => 'Dự án';

  @override
  String get freePlan2 => 'Gói miễn phí';

  @override
  String get greetingMorning => 'Chào buổi sáng';

  @override
  String get greetingAfternoon => 'Chào buổi chiều';

  @override
  String get greetingEvening => 'Chào buổi tối';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Hệ thống';

  @override
  String get noConversations => 'Chưa có cuộc trò chuyện';

  @override
  String get promptBrainstorm => 'Lên ý tưởng';

  @override
  String get promptExplain => 'Giải thích một khái niệm';

  @override
  String get promptCode => 'Giúp tôi viết code';
}
