/// Bytes, the way a person reads them.
///
/// This existed twice, identically — once in the Console session screen and
/// once in the file browser drawer — and both copies stopped at MB. On a
/// device file browser that is not hypothetical: a video, or the Alpine rootfs
/// this very app downloads, renders as "2048.0 MB" instead of "2.0 GB".
///
/// Binary units (1024), because these are file sizes shown next to a file
/// manager, and every other tool the user will compare against on the device
/// counts the same way.
String humanBytes(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
