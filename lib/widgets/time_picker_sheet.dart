import 'package:flutter/material.dart';

import '../models/search_context.dart';

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
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _grabHandle()),
            const SizedBox(height: 12),
            const Text('When?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // Open now
            _option(
              icon: Icons.schedule,
              title: 'Open now',
              onTap: () =>
                  Navigator.of(context).pop(const TimePickResult.now()),
            ),

            // Meal presets (today)
            ..._presets.map((p) => _option(
                  icon: Icons.restaurant_menu,
                  title: p.label,
                  trailing: p.sub,
                  onTap: () => Navigator.of(context).pop(
                    TimePickResult.custom(_todayApiDay, p.minutes, p.label),
                  ),
                )),

            // Pick a day & time (expandable)
            _option(
              icon: Icons.event,
              title: 'Pick a day & time',
              trailing: _showCustom ? null : '›',
              onTap: () => setState(() => _showCustom = !_showCustom),
            ),
            if (_showCustom) _buildCustom(),
          ],
        ),
      ),
    );
  }

  Widget _grabHandle() => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _option({
    required IconData icon,
    required String title,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 14),
            Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15))),
            if (trailing != null)
              Text(trailing,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildCustom() {
    return Padding(
      padding: const EdgeInsets.only(left: 34, top: 4, bottom: 4),
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
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time, size: 18),
                label: Text(SearchContext.formatClock(_selectedMinutes)),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(
                  TimePickResult.custom(
                    _selectedDay,
                    _selectedMinutes,
                    SearchContext.formatDayTime(_selectedDay, _selectedMinutes),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
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
