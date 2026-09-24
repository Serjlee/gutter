/// Whether a tab should fetch in the background now.
///
/// Only the active tab auto-fetches, every [intervalMinutes]; background
/// tabs catch up when they are activated. Never while the app window is
/// unfocused, for repositories without remotes, or while a fetch is running.
bool isAutoFetchDue({
  required DateTime now,
  required DateTime? lastFetch,
  required int intervalMinutes,
  required bool active,
  required bool focused,
  required bool hasRemotes,
  required bool fetching,
}) {
  if (!active || !focused || intervalMinutes <= 0 || !hasRemotes || fetching) {
    return false;
  }
  if (lastFetch == null) return true;
  return now.difference(lastFetch) >= Duration(minutes: intervalMinutes);
}
