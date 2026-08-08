/// A Linux distribution the user can install into the app.
///
/// Rootfs tarballs come from each project's **own** publishing infrastructure,
/// not a mirror we control. That is deliberate: these are several hundred
/// megabytes of executable code that will run on the user's phone, and the
/// shortest trustworthy path is the one the distribution itself signs and
/// serves. It also keeps us out of the redistribution business for other
/// people's GPL software.
///
/// Every entry carries a [sha256]. Downloading a rootfs and unpacking it
/// without verifying is handing arbitrary code execution to whoever can
/// intercept the connection — and unlike a normal app download, this one is
/// *designed* to be executed. The installer refuses on mismatch rather than
/// warning.
class Distro {
  const Distro({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.url,
    required this.sha256,
    required this.downloadBytes,
    required this.installedBytes,
    required this.packageManager,
    this.notes,
  });

  final String id;
  final String name;
  final String version;
  final String description;

  /// Direct URL to the aarch64 rootfs tarball, from the project's own host.
  final String url;

  /// Expected SHA-256 of the tarball. **Verified before unpacking, always.**
  final String sha256;

  final int downloadBytes;

  /// Unpacked size — the number that actually matters to someone with a full
  /// phone, and the one download UIs usually hide.
  final int installedBytes;

  /// `apt`, `apk`, `pacman` — what the user will actually type.
  final String packageManager;

  /// Anything honest that should be said before they commit to the download.
  final String? notes;

  String get sizeLabel => '${_mb(downloadBytes)} download · '
      '${_mb(installedBytes)} installed';

  /// Whether this entry's checksum has actually been filled from upstream.
  ///
  /// A placeholder hash fails the install AFTER the download — so on Kali
  /// that is 400 MB of someone's data spent to reach an error. The UI refuses
  /// to offer these rather than letting the verifier catch it late.
  bool get isVerified => !sha256.startsWith('FILL_');

  static String _mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.round()} MB';
  }
}

/// The catalogue.
///
/// **URLs and hashes are placeholders and are deliberately obviously wrong.**
/// They must be filled from each project's current published manifest and
/// checksum file at the time we ship, and refreshed when upstream rotates a
/// release — a stale hash means the download fails closed, which is the
/// correct failure. Do NOT paste a hash from a blog post or a mirror; take it
/// from the distribution's own signed checksum file.
///
/// Ordering is deliberate: Alpine first because it is the one that will
/// actually feel good on a phone. Kali is what people ask for and is a 2 GB+
/// commitment that mostly cannot use its headline tools without root.
/// The distro installed automatically when there is none.
///
/// Alpine, because 4 MB down and 9 MB installed is the difference between an
/// app that works when you open it and one that asks for a 400 MB download
/// first. Everything heavier stays an explicit choice.
const String kDefaultDistroId = 'alpine';

const List<Distro> kDistroCatalog = [
  // VERIFIED 2026-08-02: url + sha256 taken from Alpine's own
  // `latest-releases.yaml` for v3.21/aarch64, then confirmed by downloading
  // the tarball and hashing it. Refresh both together when Alpine bumps the
  // point release — a stale hash fails the install closed, which is correct.
  Distro(
    id: 'alpine',
    name: 'Alpine Linux',
    version: '3.21.7',
    description:
        'Tiny and fast. The right default on a phone — installs in seconds '
        'and leaves room for the tools you actually want.',
    url: 'https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/'
        'alpine-minirootfs-3.21.7-aarch64.tar.gz',
    sha256: 'd1d1a3fae5f4d6146e9742790a47fcb116199622cfb8439f218a4d5fbe5000da',
    downloadBytes: 3850805,
    installedBytes: 9 * 1024 * 1024,
    packageManager: 'apk',
    notes: 'musl, not glibc. A few binaries built for Debian will not run.',
  ),
  // STILL GATED 2026-08-03, and not for want of a checksum — Debian has no
  // stable URL to point at. Checked:
  //
  //  - debuerreotype/docker-debian-artifacts (the old URL here): the dist-*
  //    branches no longer carry the tarball. `rootfs.tar.xz` 404s, and the
  //    OCI blob beside it is a 16-byte git symlink. This entry could never
  //    have installed, with or without a hash.
  //  - Debian's own infrastructure publishes no rootfs tarball at all; the
  //    cloud images are qcow2/raw.
  //  - images.linuxcontainers.org does publish one, PGP-signed, but only
  //    under a dated build directory that is pruned within weeks. Pinning it
  //    would 404 rather than merely go stale — worse than not offering it.
  //
  // The remaining option is Docker Hub's registry: content-addressed, so the
  // digest is permanent, but it needs a bearer-token fetch the installer does
  // not do yet. Until then Ubuntu covers the "I want apt" case from its own
  // signed infrastructure.
  Distro(
    id: 'debian',
    name: 'Debian',
    version: '12 (bookworm)',
    description:
        'The familiar one. Real apt, the largest package archive, and what '
        'most tutorials assume.',
    url: '',
    sha256: 'FILL_NO_STABLE_UPSTREAM_URL',
    downloadBytes: 50 * 1024 * 1024,
    installedBytes: 120 * 1024 * 1024,
    packageManager: 'apt',
    notes: 'Not offered yet: Debian publishes no rootfs tarball at a stable '
        'address. Ubuntu gives you the same apt and archive.',
  ),
  // VERIFIED 2026-08-03: sha256 read from Ubuntu's own SHA256SUMS in the same
  // release directory, which is GPG-signed alongside (SHA256SUMS.gpg).
  // downloadBytes is the measured Content-Length.
  //
  // Pinned to the 24.04.4 point release, NOT a bare "24.04" — that file does
  // not exist. cdimage only publishes point-release filenames, so the old URL
  // here would have 404'd no matter what hash we paired with it. Bump both
  // together when a new point release lands.
  Distro(
    id: 'ubuntu',
    name: 'Ubuntu',
    version: '24.04.4 LTS',
    description: 'Debian with newer packages and more documentation. The '
        'straightforward choice if you want apt.',
    url: 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/'
        'ubuntu-base-24.04.4-base-arm64.tar.gz',
    sha256: '04207713ece899c3740823d33690441ad3a7f0ded1101aca744e2b0f37ac7ff2',
    downloadBytes: 29870567,
    installedBytes: 90 * 1024 * 1024,
    packageManager: 'apt',
  ),
  Distro(
    id: 'kali',
    name: 'Kali Linux',
    version: 'rolling',
    description:
        'The security distribution. Full apt access to the Kali archive.',
    // VERIFIED 2026-08-03: sha256 from Kali's own SHA256SUMS in the same
    // directory; downloadBytes is the measured Content-Length. Kali does not
    // publish a detached signature for it, unlike Ubuntu and Alpine.
    //
    // Pinned to kali-2026.2 rather than `current/`, which rolls — a rolling
    // path guarantees the hash breaks on Kali's next release. The two served
    // byte-identical files when this was taken. The old filename
    // (kalifs-arm64-minimal.tar.xz) does not exist either; it is now
    // kali-nethunter-rootfs-minimal-arm64.tar.xz.
    url: 'https://kali.download/nethunter-images/kali-2026.2/rootfs/'
        'kali-nethunter-rootfs-minimal-arm64.tar.xz',
    sha256: 'd6403a5da175df325611d23af4b92330856059c45454eced7f4cdf3ca6df2e4e',
    downloadBytes: 137313840,
    // Measured, not guessed: 846 MB unpacked on a real device.
    installedBytes: 846 * 1024 * 1024,
    packageManager: 'apt',
    // Said plainly and up front, because the gap between what people expect
    // from Kali and what it can do unrooted is enormous, and finding out after
    // a 400 MB download is the worst way to learn it.
    notes: 'PRoot is not real root. SYN scans, packet capture, monitor mode '
        'and anything needing raw sockets will NOT work — that rules out much '
        'of what Kali is known for. Connect-scans, web tooling, wordlists, '
        'scripting and analysis all work fine.',
  ),
];
