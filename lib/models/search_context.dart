/// Describes *where* and *when* the restaurant search should run.
///
/// The two dimensions are independent:
///   * **Location** — either the device's current position ("Near me", the
///     default) or a custom place the user picked (address, landmark or a point
///     dropped on the map). When custom, [lat]/[lng]/[locationLabel] are set.
///   * **Time** — either "Open now" (the default, resolved server-side by the
///     Places `openNow` filter) or a custom day + time-of-day the user chose,
///     which is filtered client-side against each place's opening hours.
///
/// The object is immutable; use the `with*`/`clear*` helpers to derive a new
/// context. [isDefault] is true when both dimensions are untouched, which lets
/// callers preserve the original (cheaper, cache-friendly) behaviour.
enum TimeMode { now, custom }

class SearchContext {
  /// Latitude of the custom search centre. Null when searching "Near me".
  final double? lat;

  /// Longitude of the custom search centre. Null when searching "Near me".
  final double? lng;

  /// Human label for the custom location (e.g. "Eiffel Tower"). Null = Near me.
  final String? locationLabel;

  final TimeMode timeMode;

  /// Target weekday, `0 = Sunday … 6 = Saturday` (matches the Places API
  /// opening-hours `day` field). Null unless [timeMode] is [TimeMode.custom].
  final int? targetDay;

  /// Target time expressed as minutes since local midnight (e.g. 8 AM = 480).
  /// Null unless [timeMode] is [TimeMode.custom].
  final int? targetMinutes;

  /// Human label for the custom time (e.g. "Breakfast", "Sun 9:00 AM").
  final String? timeLabel;

  const SearchContext({
    this.lat,
    this.lng,
    this.locationLabel,
    this.timeMode = TimeMode.now,
    this.targetDay,
    this.targetMinutes,
    this.timeLabel,
  });

  /// The initial, unmodified context: near me, open now.
  static const SearchContext initial = SearchContext();

  bool get isCustomLocation => locationLabel != null;
  bool get isCustomTime => timeMode == TimeMode.custom;

  /// True when neither dimension has been customised (near me + open now).
  bool get isDefault => !isCustomLocation && !isCustomTime;

  /// Label shown on the location pill.
  String get locationDisplay => locationLabel ?? 'Near me';

  /// Label shown on the time pill.
  String get timeDisplay => timeLabel ?? 'Open now';

  SearchContext withLocation({
    required double lat,
    required double lng,
    required String label,
  }) =>
      SearchContext(
        lat: lat,
        lng: lng,
        locationLabel: label,
        timeMode: timeMode,
        targetDay: targetDay,
        targetMinutes: targetMinutes,
        timeLabel: timeLabel,
      );

  /// Reset the location back to "Near me", keeping the time selection.
  SearchContext clearLocation() => SearchContext(
        timeMode: timeMode,
        targetDay: targetDay,
        targetMinutes: targetMinutes,
        timeLabel: timeLabel,
      );

  SearchContext withTime({
    required int day,
    required int minutes,
    required String label,
  }) =>
      SearchContext(
        lat: lat,
        lng: lng,
        locationLabel: locationLabel,
        timeMode: TimeMode.custom,
        targetDay: day,
        targetMinutes: minutes,
        timeLabel: label,
      );

  /// Reset the time back to "Open now", keeping the location selection.
  SearchContext clearTime() => SearchContext(
        lat: lat,
        lng: lng,
        locationLabel: locationLabel,
      );

  /// Stable signature used to decide whether cached results still apply.
  /// Coordinates are rounded so tiny GPS jitter does not invalidate the cache.
  String get cacheKey {
    final loc = isCustomLocation
        ? '${lat!.toStringAsFixed(4)},${lng!.toStringAsFixed(4)}'
        : 'me';
    final time = isCustomTime ? 'd$targetDay@$targetMinutes' : 'now';
    return '$loc|$time';
  }

  static const List<String> weekdayAbbr = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  /// Formats a 12-hour clock label from minutes-since-midnight, e.g. 480 → "8:00 AM".
  static String formatClock(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final period = h24 < 12 ? 'AM' : 'PM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }

  /// Builds a compact label for a custom day + time, e.g. "Sun 9:00 AM".
  static String formatDayTime(int day, int minutes) =>
      '${weekdayAbbr[day % 7]} ${formatClock(minutes)}';
}
