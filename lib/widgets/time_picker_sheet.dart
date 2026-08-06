import 'package:flutter/material.dart';

import '../models/search_context.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Outcome of the time picker. A null return from [showTimeContextPicker] means
/// the sheet was dismissed with no change.
class TimePickResult {
  final bool openNow;
  final int? day; // 0 = Sunday … 6 = Saturday
  final int? minutes; // minutes since midnight
  final String? label;

  const TimePickResult.now()
      : openNow = true,
        day = null,
        minutes = null,
        label = null;

  const TimePickResult.custom(this.day, this.minutes, this.label)
      : openNow = false;
}

class _Preset {
  final String label;
  final String sub;
  final int minutes;
  const _Preset(this.label, this.sub, this.minutes);
}

const List<_Preset> _presets = [
  _Preset('Breakfast', '8:00 AM', 8 * 60),
  _Preset('Lunch', '12:00 PM', 12 * 60),
  _Preset('Afternoon', '3:00 PM', 15 * 60),
  _Preset('Dinner', '7:00 PM', 19 * 60),
  _Preset('Late night', '10:00 PM', 22 * 60),
];

/// Presents the "search a different time" bottom sheet: "Open now" (default),
/// meal presets for today, and a "pick a day & time" option for planning ahead.
/// Presets are evaluated against each place's opening hours client-side.
Future<TimePickResult?> showTimeContextPicker(
  BuildContext context, {
  required bool isCustom,
}) {
  return showModalBottomSheet<TimePickResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TimePickerSheet(initiallyCustom: isCustom),
  );
}

class _TimePickerSheet extends StatefulWidget {
  final bool initiallyCustom;
  const _TimePickerSheet({required this.initiallyCustom});

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  bool _showCustom = false;
  // `0 = Sunday … 6 = Saturday`; DateTime uses Mon=1…Sun=7, so `% 7` maps Sun→0.
  late final int _todayApiDay = DateTime.now().weekday % 7;
  late int _selectedDay = _todayApiDay;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 12, minute: 0);

  @override
  void initState() {
    super.initState();
    _showCustom = widget.initiallyCustom;
  }

  int get _selectedMinutes => _selectedTime.hour * 60 + _selectedTime.minute;

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          0,
          0,
          0,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.sm,
              ),
              child: Text('When?',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),

            // Open now
            _option(
              icon: Icons.schedule_rounded,
              title: 'Open now',
              onTap: () =>
                  Navigator.of(context).pop(const TimePickResult.now()),
            ),

            // Meal presets (today)
            ..._presets.map((p) => _option(
                  icon: Icons.restaurant_menu_rounded,
                  title: p.label,
                  trailing: p.sub,
                  onTap: () => Navigator.of(context).pop(
                    TimePickResult.custom(_todayApiDay, p.minutes, p.label),
                  ),
                )),

            // Pick a day & time (expandable)
            _option(
              icon: Icons.event_rounded,
              title: 'Pick a day & time',
              expanded: _showCustom,
              onTap: () => setState(() => _showCustom = !_showCustom),
            ),
            if (_showCustom) _buildCustom(),
          ],
        ),
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required String title,
    String? trailing,
    bool? expanded,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
            if (trailing != null)
              Text(
                trailing,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            // A rotating chevron, rather than a literal '›' character that
            // vanished once the section was open.
            if (expanded != null)
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: AppMotion.fast,
                curve: AppMotion.standard,
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter + AppSpacing.xxl,
        AppSpacing.xs,
        AppSpacing.gutter,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day chips: Today, Tomorrow, then the rest of the week.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (offset) {
              final day = (_todayApiDay + offset) % 7;
              final label = offset == 0
                  ? 'Today'
                  : offset == 1
                      ? 'Tomorrow'
                      : SearchContext.weekdayAbbr[day];
              final selected = day == _selectedDay;
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => setState(() => _selectedDay = day),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time_rounded, size: 18),
                label: Text(SearchContext.formatClock(_selectedMinutes)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  TimePickResult.custom(
                    _selectedDay,
                    _selectedMinutes,
                    SearchContext.formatDayTime(_selectedDay, _selectedMinutes),
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
