// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppL10nId extends AppL10n {
  AppL10nId([String locale = 'id']) : super(locale);

  @override
  String get appName => 'CyberNeurova';

  @override
  String get signIn => 'Masuk';

  @override
  String get signUp => 'Daftar';

  @override
  String get signOut => 'Keluar';

  @override
  String get signInToContinue => 'Masuk untuk melanjutkan';

  @override
  String get createAccount => 'Buat akun';

  @override
  String get joinCyberNeurovaFree => 'Bergabunglah dengan CyberNeurova gratis';

  @override
  String get email => 'Email';

  @override
  String get password => 'Kata sandi';

  @override
  String get nameOptional => 'Nama (opsional)';

  @override
  String get forgotPassword => 'Lupa kata sandi?';

  @override
  String get dontHaveAccount => 'Belum punya akun? Daftar';

  @override
  String get alreadyHaveAccount => 'Sudah punya akun? Masuk';

  @override
  String get orDivider => 'ATAU';

  @override
  String get continueWithGoogle => 'Lanjut dengan Google';

  @override
  String get continueWithApple => 'Lanjut dengan Apple';

  @override
  String get enterValidEmail => 'Masukkan email yang valid';

  @override
  String get passwordTooShort => 'Kata sandi terlalu pendek';

  @override
  String get passwordMin8 => 'Minimal 8 karakter';

  @override
  String get enterYourPassword => 'Masukkan kata sandi';

  @override
  String get resetPassword => 'Atur ulang kata sandi';

  @override
  String get resetPasswordHint =>
      'Masukkan email akun Anda, kami akan mengirimkan tautan untuk mengatur ulang kata sandi.';

  @override
  String get sendResetLink => 'Kirim tautan';

  @override
  String get backToSignIn => 'Kembali ke masuk';

  @override
  String get checkYourEmail => 'Periksa email Anda';

  @override
  String resetSentBody(String email) {
    return 'Jika akun untuk $email ada, tautan pengaturan ulang sedang dikirim. Periksa folder spam jika tidak menemukannya.';
  }

  @override
  String get verifyEmailTitle => 'Periksa email Anda';

  @override
  String verifyEmailBody(String email) {
    return 'Kami mengirim tautan verifikasi ke $email. Ketuk tautan untuk mengaktifkan akun, lalu masuk.';
  }

  @override
  String get ok => 'OK';

  @override
  String get chats => 'Obrolan';

  @override
  String get images => 'Gambar';

  @override
  String get discover => 'Jelajah';

  @override
  String get profile => 'Profil';

  @override
  String get noChatsYet => 'Belum ada percakapan';

  @override
  String get startChattingHint => 'Mulai mengobrol dengan CyberNeurova AI';

  @override
  String get newConversation => 'Percakapan baru';

  @override
  String get messageInputHint => 'Pesan ke CyberNeurova...';

  @override
  String get howCanIHelp => 'Apa yang bisa saya bantu hari ini?';

  @override
  String get search => 'Cari';

  @override
  String get searchChatsHint => 'Cari obrolan…';

  @override
  String get typeToSearchChats => 'Ketik untuk mencari obrolan Anda';

  @override
  String noChatsMatch(String query) {
    return 'Tidak ada obrolan yang cocok dengan \"$query\"';
  }

  @override
  String get rename => 'Ganti nama';

  @override
  String get deleteChat => 'Hapus obrolan';

  @override
  String get deleteChatQuestion => 'Hapus obrolan?';

  @override
  String get cannotBeUndone => 'Tindakan ini tidak dapat dibatalkan.';

  @override
  String get cancel => 'Batal';

  @override
  String get delete => 'Hapus';

  @override
  String get save => 'Simpan';

  @override
  String get retry => 'Coba lagi';

  @override
  String get copiedToClipboard => 'Disalin ke papan klip';

  @override
  String get waitForResponseToFinish => 'Tunggu hingga respons selesai.';

  @override
  String get noImagesYet => 'Belum ada gambar';

  @override
  String get tapGenerateHint => 'Ketuk Buat untuk membuat gambar pertama Anda';

  @override
  String get generate => 'Buat';

  @override
  String get generateImage => 'Buat gambar';

  @override
  String get describeImage => 'Deskripsikan gambar yang Anda inginkan...';

  @override
  String get yourImageWillAppear => 'Gambar Anda akan muncul di sini';

  @override
  String get starting => 'Memulai...';

  @override
  String generatingPercent(int percent) {
    return 'Membuat $percent%';
  }

  @override
  String get generateAnother => 'Buat lagi';

  @override
  String get generationFailed => 'Pembuatan gagal';

  @override
  String get trending => 'Tren';

  @override
  String get recent => 'Terbaru';

  @override
  String get nothingToDiscover => 'Belum ada yang bisa dijelajahi';

  @override
  String get freePlan => 'Paket Gratis';

  @override
  String get premiumPlan => 'Paket Premium';

  @override
  String get proPlan => 'Paket Pro';

  @override
  String get proMaxPlan => 'Paket Pro Max';

  @override
  String get upgrade => 'Tingkatkan';

  @override
  String get upgradeHint => 'Tingkatkan untuk lebih banyak token & model';

  @override
  String get tokenUsage => 'Penggunaan token';

  @override
  String get used => 'terpakai';

  @override
  String get limit => 'batas';

  @override
  String get settings => 'Pengaturan';

  @override
  String get notifications => 'Notifikasi';

  @override
  String get changePassword => 'Ubah kata sandi';

  @override
  String get language => 'Bahasa';

  @override
  String get account => 'Akun';

  @override
  String get editProfile => 'Edit profil';

  @override
  String get activeSessions => 'Sesi aktif';

  @override
  String get deleteAccount => 'Hapus akun';

  @override
  String get deleteAccountConfirm =>
      'Hapus akun Anda secara permanen? Tindakan ini tidak dapat dibatalkan.';

  @override
  String get deleteAccountPasswordOptional =>
      'Kosongkan jika Anda masuk dengan Google atau Apple.';

  @override
  String get signOutQuestion => 'Keluar?';

  @override
  String get signOutBody => 'Anda perlu masuk lagi.';

  @override
  String get voiceInput => 'Input suara';

  @override
  String get voiceInputHint => 'Tahan untuk merekam, lepas untuk mengirim.';

  @override
  String get voiceTranscribing => 'Mentranskripsi…';

  @override
  String get voicePermissionDenied => 'Izin mikrofon ditolak.';

  @override
  String get attach => 'Lampirkan';

  @override
  String get takePhoto => 'Ambil foto';

  @override
  String get fromLibrary => 'Dari galeri';

  @override
  String get uploadingFile => 'Mengunggah…';

  @override
  String get shareChat => 'Bagikan obrolan';

  @override
  String get visibility => 'Visibilitas';

  @override
  String get visibilityPrivate => 'Pribadi';

  @override
  String get visibilityShared => 'Dibagikan dengan orang tertentu';

  @override
  String get visibilityPublic => 'Tautan publik';

  @override
  String get shareWithEmail => 'Bagikan dengan seseorang (email)';

  @override
  String get addPerson => 'Tambah';

  @override
  String get copyLink => 'Salin tautan';

  @override
  String get linkCopied => 'Tautan disalin';

  @override
  String get errorGeneric => 'Terjadi kesalahan. Silakan coba lagi.';

  @override
  String get errorNetwork => 'Tidak ada koneksi internet.';

  @override
  String get errorSessionExpired => 'Sesi berakhir. Silakan masuk kembali.';

  @override
  String errorRateLimited(int seconds) {
    return 'Terlalu banyak permintaan. Coba lagi dalam $seconds dtk.';
  }

  @override
  String get errorQuotaExceeded => 'Kuota token terlampaui.';

  @override
  String get errorServer => 'Kesalahan server. Coba lagi nanti.';

  @override
  String get couldNotOpenBrowser => 'Tidak dapat membuka browser.';

  @override
  String get comingSoon => 'Segera hadir';

  @override
  String get newChat => 'Obrolan baru';

  @override
  String get media => 'Media';

  @override
  String get research => 'Riset';

  @override
  String get recents => 'Terbaru';

  @override
  String get workspace => 'Workspace';

  @override
  String get chatsWillAppearHere => 'Obrolan Anda akan tampil di sini';

  @override
  String get billing => 'Penagihan';

  @override
  String get usageLabel => 'Penggunaan';

  @override
  String get customPrompts => 'Prompt khusus';

  @override
  String get memory => 'Memori';

  @override
  String get capabilities => 'Kemampuan';

  @override
  String get designLab => 'Lab Desain';

  @override
  String get skills => 'Keterampilan';

  @override
  String get tools => 'Alat';

  @override
  String get premiumRequired => 'Fitur Premium — tingkatkan untuk mengaktifkan';

  @override
  String get memoryEmptyTitle => 'Belum ada memori';

  @override
  String get memoryEmptyHint =>
      'CyberNeurova akan menyimpan konteks penting dari obrolan Anda di sini.';

  @override
  String get memoryAtCapacity => 'Memori penuh — entri terlama akan diganti.';

  @override
  String memoryCapacityWarning(int percent) {
    return 'Memori hampir penuh ($percent%)';
  }

  @override
  String memoryLastExtracted(String when) {
    return 'Ekstraksi terakhir $when';
  }

  @override
  String get categoryPreferences => 'Preferensi';

  @override
  String get categoryFacts => 'Fakta';

  @override
  String get categoryProjects => 'Proyek';

  @override
  String get categoryPatterns => 'Pola';

  @override
  String get categoryContext => 'Konteks';

  @override
  String get researchAll => 'Semua';

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
  String get newResearch => 'Riset baru';

  @override
  String get noResearchYet => 'Belum ada riset';

  @override
  String get researchEmptyHint =>
      'Mulai riset baru untuk menyelidiki CVE, exploit, atau ancaman.';

  @override
  String get sources => 'Sumber';

  @override
  String get close => 'Tutup';

  @override
  String get doneLabel => 'Selesai';

  @override
  String get projectsTitle => 'Proyek';

  @override
  String get freePlan2 => 'Paket gratis';

  @override
  String get greetingMorning => 'Selamat pagi';

  @override
  String get greetingAfternoon => 'Selamat siang';

  @override
  String get greetingEvening => 'Selamat malam';

  @override
  String greetingWithName(String period, String name) {
    return '$period, $name';
  }

  @override
  String get system => 'Sistem';

  @override
  String get noConversations => 'Belum ada percakapan';

  @override
  String get promptBrainstorm => 'Curah ide';

  @override
  String get promptExplain => 'Jelaskan konsep';

  @override
  String get promptCode => 'Bantu saya menulis kode';
}
