import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/places_lookup_service.dart';

/// Full-screen "drop a pin" picker. The map pans underneath a *fixed* centre pin
/// (the standard, clutter-free pattern — no tap-to-place), the centre coordinate
/// is reverse-geocoded into an address shown in the top card, and "Search this
/// area" returns the chosen [PlaceResult] to the caller.
class MapPickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const MapPickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late double _centerLat = widget.initialLat;
  late double _centerLng = widget.initialLng;
  String _address = '';
  bool _resolving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onCameraMove(CameraPosition position) {
    _centerLat = position.target.latitude;
    _centerLng = position.target.longitude;
  }

  void _onCameraIdle() {
    // Debounce so a flick that ends in several idle events resolves once.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _resolveAddress);
  }

  Future<void> _resolveAddress() async {
    setState(() => _resolving = true);
    final address = await PlaceLookupService.instance
        .reverseGeocode(_centerLat, _centerLng);
    if (!mounted) return;
    setState(() {
      _address = address;
      _resolving = false;
    });
  }

  void _confirm() {
    // Use the first line of the address as the short pill label.
    final label = _address.isNotEmpty
        ? _address.split(',').first.trim()
        : 'Pinned location';
    Navigator.of(context).pop(PlaceResult(
      lat: _centerLat,
      lng: _centerLng,
      label: label,
      address: _address,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Pick a point',
            style: TextStyle(color: Colors.black, fontSize: 16)),
        backgroundColor: Colors.grey[200],
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.initialLat, widget.initialLng),
              zoom: 15,
            ),
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Fixed centre pin. Nudged up by half the icon height so the point
          // sits on the map centre, with a small shadow dot beneath it.
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place, size: 44, color: Colors.red),
                Container(
                  width: 8,
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 44), // offset so the tip marks centre
              ],
            ),
          ),

          // Address card at the top.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 18, color: Colors.black54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _resolving
                          ? const Text('Finding address…',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black54))
                          : Text(
                              _address.isEmpty ? 'Move the map to a point' : _address,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Confirm button at the bottom.
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: ElevatedButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search this area'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
