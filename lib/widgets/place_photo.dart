import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/restaurant_service.dart';
import 'shimmer.dart';

/// A Places photo, fetched when it first appears rather than up front.
///
/// Two things used to go wrong here. Every photo in a result set was downloaded
/// before the list was allowed to render, so twenty images stood between the
/// user and a screen they could already read. And each was then decoded at the
/// full 800×450 it was fetched at no matter how small it was drawn — a 1.4 MB
/// bitmap behind a 60pt thumbnail.
///
/// This asks for a photo only once it is actually built, shares one download
/// between everything showing the same photo (see [RestaurantService.loadPhoto])
/// and decodes it near the size it will occupy.
class PlacePhoto extends StatefulWidget {
  final String photoRef;

  /// Null means "as wide as the parent allows" — the card header stretches,
  /// where a list thumbnail is a fixed box.
  final double? width;
  final double height;
  final BoxFit fit;

  /// True for the single photo a place displays on its row and card face.
  /// Those jump the download queue, so every place gets its one picture before
  /// any place gets a second.
  final bool priority;

  const PlacePhoto({
    super.key,
    required this.photoRef,
    required this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.priority = false,
  });

  @override
  State<PlacePhoto> createState() => _PlacePhotoState();
}

class _PlacePhotoState extends State<PlacePhoto> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PlacePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoRef != widget.photoRef) {
      _bytes = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    final service = RestaurantService.instance;
    final cached = service.getCachedPhoto(widget.photoRef);
    if (cached != null) {
      // Already in memory: assign directly, since both call sites are followed
      // by a build. Going through setState here would be a no-op rebuild.
      _bytes = cached;
      return;
    }

    final ref = widget.photoRef;
    service.loadPhoto(ref, priority: widget.priority).then((bytes) {
      // A recycled list row may have been rebound to a different photo while
      // this was in flight.
      if (!mounted || ref != widget.photoRef) return;
      setState(() {
        _bytes = bytes;
        _failed = bytes == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return _placeholder();

    return Image.memory(
      bytes,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      // Only the height is constrained so the decode keeps the source's aspect
      // ratio — pinning both dimensions would stretch a landscape photo into a
      // square thumbnail. BoxFit does the cropping.
      cacheHeight:
          (widget.height * MediaQuery.devicePixelRatioOf(context)).round(),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  /// A shimmering block while the photo is in flight, and a flat one once it
  /// has failed — a shimmer implies something is still coming.
  ///
  /// Deliberately not a spinner per row: twenty rows would mean twenty
  /// animation controllers. Every ShimmerBox shares one ticker.
  Widget _placeholder() {
    if (_failed) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[300],
        child: Icon(Icons.image_not_supported_outlined,
            size: widget.height * 0.3, color: Colors.grey[500]),
      );
    }
    return ShimmerBox(width: widget.width, height: widget.height);
  }
}
