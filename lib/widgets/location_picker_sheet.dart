import 'dart:async';
import 'package:flutter/material.dart';

import '../screens/map_picker_screen.dart';
import '../services/places_lookup_service.dart';
import '../theme/app_spacing.dart';

/// Outcome of the location picker. Either the user asked to go back to their
/// current GPS location, or they picked a specific [place]. A null return from
/// [showLocationPicker] means the sheet was dismissed with no change.
class LocationPickResult {
  final bool useCurrentLocation;
  final PlaceResult? place;

  const LocationPickResult.currentLocation()
      : useCurrentLocation = true,
        place = null;

  const LocationPickResult.place(this.place) : useCurrentLocation = false;
}

/// Presents the "search a different place" bottom sheet: an autocomplete search
/// for addresses & landmarks, a "use my current location" shortcut, a "pick on
/// map" entry, and recent locations. [biasLat]/[biasLng] bias the predictions
/// toward the current search area and seed the map picker.
Future<LocationPickResult?> showLocationPicker(
  BuildContext context, {
  required double biasLat,
  required double biasLng,
}) {
  // Background, radius and drag handle all come from the shared
  // BottomSheetThemeData now, so both sheets are certain to match.
  return showModalBottomSheet<LocationPickResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LocationPickerSheet(biasLat: biasLat, biasLng: biasLng),
  );
}

class _LocationPickerSheet extends StatefulWidget {
  final double biasLat;
  final double biasLng;

  const _LocationPickerSheet({required this.biasLat, required this.biasLng});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  final String _sessionToken = PlaceLookupService.newSessionToken();
  Timer? _debounce;
  List<PlacePrediction> _predictions = const [];
  List<PlaceResult> _recents = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final recents = await PlaceLookupService.instance.getRecents();
    if (!mounted) return;
    setState(() => _recents = recents);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _predictions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await PlaceLookupService.instance.autocomplete(
        value,
        sessionToken: _sessionToken,
        biasLat: widget.biasLat,
        biasLng: widget.biasLng,
      );
      if (!mounted) return;
      setState(() => _predictions = results);
    });
  }

  Future<void> _pickPrediction(PlacePrediction prediction) async {
    setState(() => _loading = true);
    final place = await PlaceLookupService.instance
        .placeDetails(prediction.placeId, sessionToken: _sessionToken);
    if (!mounted) return;
    setState(() => _loading = false);
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load that place. Try again.')),
      );
      return;
    }
    await PlaceLookupService.instance.addRecent(place);
    if (!mounted) return;
    Navigator.of(context).pop(LocationPickResult.place(place));
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLat: widget.biasLat,
          initialLng: widget.biasLng,
        ),
      ),
    );
    if (result == null || !mounted) return;
    await PlaceLookupService.instance.addRecent(result);
    if (!mounted) return;
    Navigator.of(context).pop(LocationPickResult.place(result));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final searching = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.md,
              ),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Search address or place',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: searching
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        )
                      : null,
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: searching
                  ? _buildPredictions()
                  : _buildDefaultList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictions() {
    if (_predictions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'No matches yet — keep typing.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _predictions.length,
      itemBuilder: (context, i) {
        final p = _predictions[i];
        return ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(p.mainText, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: p.secondaryText.isEmpty
              ? null
              : Text(p.secondaryText,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _pickPrediction(p),
        );
      },
    );
  }

  Widget _buildDefaultList() {
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: Icon(Icons.my_location_rounded,
              color: Theme.of(context).colorScheme.primary),
          title: const Text('Use my current location'),
          onTap: () => Navigator.of(context)
              .pop(const LocationPickResult.currentLocation()),
        ),
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: const Text('Pick on map'),
          onTap: _pickOnMap,
        ),
        if (_recents.isNotEmpty) ...[
          const Divider(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.xs,
            ),
            child: Text(
              'RECENT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          ..._recents.map((r) => ListTile(
                leading: const Icon(Icons.history),
                title:
                    Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: r.address.isEmpty
                    ? null
                    : Text(r.address,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context)
                    .pop(LocationPickResult.place(r)),
              )),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
