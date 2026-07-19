import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/restaurant.dart';

/// A movable, zoomable map of the current result set. Each restaurant that has
/// real coordinates gets a pin carrying its rank, drawn to match the amber rank
/// badge on the card; tapping one hands its index back to the caller, which
/// flips over to that restaurant's card.
class RestaurantMapView extends StatefulWidget {
  final List<Restaurant> restaurants;

  /// Centre of the current search — used as the camera fallback when no
  /// restaurant has usable coordinates.
  final double? currentLat;
  final double? currentLng;

  /// Index into [restaurants] of the tapped marker.
  final void Function(int index) onRestaurantTap;

  const RestaurantMapView({
    super.key,
    required this.restaurants,
    required this.currentLat,
    required this.currentLng,
    required this.onRestaurantTap,
  });

  @override
  State<RestaurantMapView> createState() => _RestaurantMapViewState();
}

class _RestaurantMapViewState extends State<RestaurantMapView> {
  GoogleMapController? _controller;
  Set<Marker> _markers = {};

  /// Pins are rasterised per rank, so identical ranks across rebuilds reuse the
  /// same bitmap instead of re-drawing to a canvas.
  static final Map<int, BitmapDescriptor> _pinCache = {};

  @override
  void initState() {
    super.initState();
    _rebuildMarkers();
  }

  @override
  void didUpdateWidget(RestaurantMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.restaurants, widget.restaurants)) {
      _rebuildMarkers();
    }
  }

  /// Restaurants parse to (0, 0) when the API omits a location, so drop those
  /// rather than drawing null-island markers off the coast of Africa.
  List<MapEntry<int, Restaurant>> get _plottable {
    final entries = <MapEntry<int, Restaurant>>[];
    for (var i = 0; i < widget.restaurants.length; i++) {
      final loc = widget.restaurants[i].location;
      if (loc.latitude == 0 && loc.longitude == 0) continue;
      entries.add(MapEntry(i, widget.restaurants[i]));
    }
    return entries;
  }

  Future<void> _rebuildMarkers() async {
    final markers = <Marker>{};
    for (final entry in _plottable) {
      final index = entry.key;
      final restaurant = entry.value;
      final rank = restaurant.rank ?? index + 1;
      markers.add(Marker(
        markerId: MarkerId(restaurant.id),
        position: LatLng(
          restaurant.location.latitude,
          restaurant.location.longitude,
        ),
        icon: await _rankPin(rank),
        infoWindow: InfoWindow(title: '$rank. ${restaurant.name}'),
        onTap: () => widget.onRestaurantTap(index),
      ));
    }
    if (!mounted) return;
    setState(() => _markers = markers);
  }

  /// Draws an amber, numbered map pin mirroring the rank badge on the card.
  /// Rasterised at 3x and handed back with a matching pixel ratio so it stays
  /// crisp without dwarfing the map.
  Future<BitmapDescriptor> _rankPin(int rank) async {
    final cached = _pinCache[rank];
    if (cached != null) return cached;

    const width = 108.0;
    const height = 132.0;
    const centre = Offset(width / 2, width / 2);
    const radius = width / 2 - 4;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Tail first, so the circle's white ring paints over its shoulders.
    final tail = Path()
      ..moveTo(centre.dx - 15, centre.dy + radius - 6)
      ..lineTo(centre.dx, height - 2)
      ..lineTo(centre.dx + 15, centre.dy + radius - 6)
      ..close();
    canvas.drawPath(tail, Paint()..color = Colors.amber);

    canvas.drawCircle(centre, radius, Paint()..color = Colors.amber);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    final label = TextPainter(
      text: TextSpan(
        text: '$rank',
        style: TextStyle(
          color: Colors.black,
          // Shrink so three-digit ranks still fit inside the circle.
          fontSize: rank >= 100 ? 36 : 48,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(centre.dx - label.width / 2, centre.dy - label.height / 2),
    );

    final image =
        await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final pin = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: 3,
    );
    _pinCache[rank] = pin;
    return pin;
  }

  CameraPosition get _initialCamera {
    final plottable = _plottable;
    if (plottable.isNotEmpty) {
      final first = plottable.first.value.location;
      return CameraPosition(
        target: LatLng(first.latitude, first.longitude),
        zoom: 14,
      );
    }
    return CameraPosition(
      target: LatLng(widget.currentLat ?? 0, widget.currentLng ?? 0),
      zoom: 14,
    );
  }

  /// Frame every marker once the map is ready. A single marker has no bounds
  /// worth fitting, so it just gets a sensible zoom instead.
  Future<void> _fitToMarkers() async {
    final controller = _controller;
    final plottable = _plottable;
    if (controller == null || plottable.length < 2) return;

    var minLat = plottable.first.value.location.latitude;
    var maxLat = minLat;
    var minLng = plottable.first.value.location.longitude;
    var maxLng = minLng;
    for (final entry in plottable) {
      final loc = entry.value.location;
      if (loc.latitude < minLat) minLat = loc.latitude;
      if (loc.latitude > maxLat) maxLat = loc.latitude;
      if (loc.longitude < minLng) minLng = loc.longitude;
      if (loc.longitude > maxLng) maxLng = loc.longitude;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        48, // padding so edge pins aren't flush against the frame
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_plottable.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "None of these restaurants have a location we can map.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return GoogleMap(
      initialCameraPosition: _initialCamera,
      markers: _markers,
      onMapCreated: (controller) {
        _controller = controller;
        _fitToMarkers();
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}
