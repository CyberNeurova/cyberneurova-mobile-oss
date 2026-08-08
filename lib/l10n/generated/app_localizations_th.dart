// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppL10nTh extends AppL10n {
  AppL10nTh([String locale = 'th']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'เข้าสู่ระบบ';

  @override
  String get signUp => 'สมัครสมาชิก';

  @override
  String get signOut => 'ออกจากระบบ';

  @override
  String get signInToContinue => 'เข้าสู่ระบบเพื่อดำเนินการต่อ';

  @override
  String get createAccount => 'สร้างบัญชี';

  @override
  String get joinCyberNeurovaFree => 'เข้าร่วม CyberNeurova ฟรี';

  @override
  String get email => 'อีเมล';

  @override
  String get password => 'รหัสผ่าน';

  @override
  String get nameOptional => 'ชื่อ (ไม่บังคับ)';

  @override
  String get forgotPassword => 'ลืมรหัสผ่าน?';

  @override
  String get dontHaveAccount => 'ยังไม่มีบัญชี? สมัครสมาชิก';

  @override
  String get alreadyHaveAccount => 'มีบัญชีอยู่แล้ว? เข้าสู่ระบบ';

  @override
  String get orDivider => 'หรือ';

  @override
  String get continueWithGoogle => 'ดำเนินการต่อด้วย Google';

  @override
  String get continueWithApple => 'ดำเนินการต่อด้วย Apple';

  @override
  String get enterValidEmail => 'ใส่อีเมลที่ถูกต้อง';

  @override
  String get passwordTooShort => 'รหัสผ่านสั้นเกินไป';

  @override
  String get passwordMin8 => 'อย่างน้อย 8 ตัวอักษร';

  @override
  String get enterYourPassword => 'ใส่รหัสผ่านของคุณ';

  @override
  String get resetPassword => 'รีเซ็ตรหัสผ่าน';

  @override
  String get resetPasswordHint =>
      'ใส่อีเมลของบัญชีคุณ แล้วเราจะส่งลิงก์รีเซ็ตรหัสผ่านให้';

  @override
  String get sendResetLink => 'ส่งลิงก์รีเซ็ต';

  @override
  String get backToSignIn => 'กลับไปที่หน้าเข้าสู่ระบบ';

  @override
  String get checkYourEmail => 'ตรวจสอบอีเมลของคุณ';

  @override
  String resetSentBody(String email) {
    return 'หากมีบัญชีสำหรับ $email ลิงก์รีเซ็ตจะถูกส่งไป ตรวจสอบโฟลเดอร์สแปมหากไม่พบ';
  }

  @override
  String get verifyEmailTitle => 'ตรวจสอบอีเมลของคุณ';

  @override
  String verifyEmailBody(String email) {
    return 'เราได้ส่งลิงก์ยืนยันไปที่ $email แตะลิงก์เพื่อเปิดใช้งานบัญชี แล้วเข้าสู่ระบบ';
  }

  @override
  String get ok => 'ตกลง';

  @override
  String get chats => 'แชท';

  @override
  String get images => 'รูปภาพ';

  @override
  String get discover => 'ค้นพบ';

  @override
  String get profile => 'โปรไฟล์';

  @override
  String get noChatsYet => 'ยังไม่มีการสนทนา';

  @override
  String get startChattingHint => 'เริ่มแชทกับ CyberNeurova AI';

  @override
  String get newConversation => 'การสนทนาใหม่';

  @override
  String get messageInputHint => 'ส่งข้อความถึง CyberNeurova...';

  @override
  String get howCanIHelp => 'วันนี้ให้ช่วยอะไรดี?';

  @override
  String get search => 'ค้นหา';

  @override
  String get searchChatsHint => 'ค้นหาแชท…';

  @override
  String get typeToSearchChats => 'พิมพ์เพื่อค้นหาในแชทของคุณ';

  @override
  String noChatsMatch(String query) {
    return 'ไม่พบแชทที่ตรงกับ \"$query\"';
  }

  @override
  String get rename => 'เปลี่ยนชื่อ';

  @override
  String get deleteChat => 'ลบแชท';

  @override
  String get deleteChatQuestion => 'ลบแชท?';

  @override
  String get cannotBeUndone => 'ไม่สามารถยกเลิกได้';

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get delete => 'ลบ';

  @override
  String get save => 'บันทึก';

  @override
  String get retry => 'ลองอีกครั้ง';

  @override
  String get copiedToClipboard => 'คัดลอกไปยังคลิปบอร์ดแล้ว';

  @override
  String get waitForResponseToFinish => 'โปรดรอให้คำตอบเสร็จสิ้น';

  @override
  String get noImagesYet => 'ยังไม่มีรูปภาพ';

  @override
  String get tapGenerateHint => 'แตะ สร้าง เพื่อสร้างรูปภาพแรก';

  @override
  String get generate => 'สร้าง';

  @override
  String get generateImage => 'สร้างรูปภาพ';

  @override
  String get describeImage => 'อธิบายรูปภาพที่คุณต้องการ...';

  @override
  String get yourImageWillAppear => 'รูปภาพของคุณจะปรากฏที่นี่';

  @override
  String get starting => 'กำลังเริ่ม...';

  @override
  String generatingPercent(int percent) {
    return 'กำลังสร้าง $percent%';
  }

  @override
  String get generateAnother => 'สร้างอีกครั้ง';

  @override
  String get generationFailed => 'การสร้างล้มเหลว';

  @override
  String get trending => 'กำลังมาแรง';

  @override
  String get recent => 'ล่าสุด';

  @override
  String get nothingToDiscover => 'ยังไม่มีสิ่งที่ค้นพบ';

  @override
  String get freePlan => 'แพ็กเกจฟรี';

  @override
  String get premiumPlan => 'แพ็กเกจ Premium';

  @override
  String get proPlan => 'แพ็กเกจ Pro';

  @override
  String get proMaxPlan => 'แพ็กเกจ Pro Max';

  @override
  String get upgrade => 'อัปเกรด';

  @override
  String get upgradeHint => 'อัปเกรดเพื่อรับโทเค็นและโมเดลเพิ่ม';

  @override
  String get tokenUsage => 'การใช้โทเค็น';

  @override
  String get used => 'ใช้ไป';

  @override
  String get limit => 'ขีดจำกัด';

  @override
  String get settings => 'การตั้งค่า';

  @override
  String get notifications => 'การแจ้งเตือน';

  @override
  String get changePassword => 'เปลี่ยนรหัสผ่าน';

  @override
  String get language => 'ภาษา';

  @override
  String get account => 'บัญชี';

  @override
  String get editProfile => 'แก้ไขโปรไฟล์';

  @override
  String get activeSessions => 'เซสชันที่ใช้งานอยู่';

  @override
  String get deleteAccount => 'ลบบัญชี';

  @override
  String get deleteAccountConfirm =>
      'ลบบัญชีของคุณอย่างถาวร? ไม่สามารถยกเลิกได้';

  @override
  String get deleteAccountPasswordOptional =>
      'เว้นว่างไว้หากคุณลงชื่อเข้าใช้ด้วย Google หรือ Apple';

  @override
  String get signOutQuestion => 'ออกจากระบบ?';

  @override
  String get signOutBody => 'คุณจะต้องเข้าสู่ระบบอีกครั้ง';

  @override
  String get voiceInput => 'ป้อนด้วยเสียง';

  @override
  String get voiceInputHint => 'กดค้างเพื่อบันทึก ปล่อยเพื่อส่ง';

  @override
  String get voiceTranscribing => 'กำลังถอดเสียง…';

  @override
  String get voicePermissionDenied => 'ไม่ได้รับอนุญาตให้ใช้ไมโครโฟน';

  @override
  String get attach => 'แนบไฟล์';

  @override
  String get takePhoto => 'ถ่ายรูป';

  @override
  String get fromLibrary => 'จากคลังภาพ';

  @override
  String get uploadingFile => 'กำลังอัปโหลด…';

  @override
  String get shareChat => 'แชร์แชท';

  @override
  String get visibility => 'การมองเห็น';

  @override
  String get visibilityPrivate => 'ส่วนตัว';

  @override
  String get visibilityShared => 'แชร์กับบุคคลที่ระบุ';

  @override
  String get visibilityPublic => 'ลิงก์สาธารณะ';

  @override
  String get shareWithEmail => 'แชร์กับใครบางคน (อีเมล)';

  @override
  String get addPerson => 'เพิ่ม';

  @override
  String get copyLink => 'คัดลอกลิงก์';

  @override
  String get linkCopied => 'คัดลอกลิงก์แล้ว';

  @override
  String get errorGeneric => 'เกิดข้อผิดพลาด กรุณาลองอีกครั้ง';

  @override
  String get errorNetwork => 'ไม่มีการเชื่อมต่ออินเทอร์เน็ต';

  @override
  String get errorSessionExpired => 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง';

  @override
  String errorRateLimited(int seconds) {
    return 'คำขอมากเกินไป ลองอีกครั้งใน $seconds วินาที';
  }

  @override
  String get errorQuotaExceeded => 'ใช้โควตาโทเค็นเกินแล้ว';

  @override
  String get errorServer => 'เซิร์ฟเวอร์ผิดพลาด กรุณาลองใหม่ภายหลัง';

  @override
  String get couldNotOpenBrowser => 'ไม่สามารถเปิดเบราว์เซอร์ได้';

  @override
  String get comingSoon => 'เร็ว ๆ นี้';

  @override
  String get newChat => 'แชทใหม่';

  @override
  String get media => 'สื่อ';

  @override
  String get research => 'การวิจัย';

  @override
  String get recents => 'ล่าสุด';

  @override
  String get chatsWillAppearHere => 'แชทของคุณจะแสดงที่นี่';

  @override
  String get billing => 'การเรียกเก็บเงิน';

  @override
  String get usageLabel => 'การใช้งาน';

  @override
  String get customPrompts => 'พรอมต์ที่กำหนดเอง';

  @override
  String get memory => 'หน่วยความจำ';

  @override
  String get capabilities => 'ความสามารถ';

  @override
  String get designLab => 'ห้องแล็บออกแบบ';

  @override
  String get skills => 'ทักษะ';

  @override
  String get tools => 'เครื่องมือ';

  @override
  String get premiumRequired => 'คุณสมบัติพรีเมียม — อัปเกรดเพื่อเปิดใช้งาน';

  @override
  String get memoryEmptyTitle => 'ยังไม่มีหน่วยความจำ';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova จะบันทึกบริบทสำคัญจากแชทของคุณที่นี่';

  @override
  String get memoryAtCapacity => 'หน่วยความจำเต็ม — รายการเก่าสุดจะถูกแทนที่';

  @override
  String memoryCapacityWarning(int percent) {
    return 'หน่วยความจำเกือบเต็ม ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'สกัดล่าสุด $when';
  }

  @override
  String get categoryPreferences => 'ความชอบ';

  @override
  String get categoryFacts => 'ข้อเท็จจริง';

  @override
  String get categoryProjects => 'โครงการ';

  @override
  String get categoryPatterns => 'รูปแบบ';

  @override
  String get categoryContext => 'บริบท';

  @override
  String get researchAll => 'ทั้งหมด';

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
  String get newResearch => 'การวิจัยใหม่';

  @override
  String get noResearchYet => 'ยังไม่มีการวิจัย';

  @override
  String get researchEmptyHint =>
      'เริ่มการวิจัยใหม่เพื่อตรวจสอบ CVE, exploit หรือภัยคุกคาม';

  @override
  String get sources => 'แหล่งที่มา';

  @override
  String get close => 'ปิด';

  @override
  String get doneLabel => 'เสร็จสิ้น';

  @override
  String get projectsTitle => 'โครงการ';

  @override
  String get freePlan2 => 'แพ็กเกจฟรี';

  @override
  String get greetingMorning => 'สวัสดีตอนเช้า';

  @override
  String get greetingAfternoon => 'สวัสดีตอนบ่าย';

  @override
  String get greetingEvening => 'สวัสดีตอนเย็น';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'ระบบ';

  @override
  String get noConversations => 'ยังไม่มีการสนทนา';

  @override
  String get promptBrainstorm => 'ระดมความคิด';

  @override
  String get promptExplain => 'อธิบายแนวคิด';

  @override
  String get promptCode => 'ช่วยฉันเขียนโค้ด';
}
