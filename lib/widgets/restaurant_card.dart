import 'dart:collection';

import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'place_photo.dart';
import 'place_status_icon.dart';

class RestaurantCard extends StatefulWidget {
  /// Which photo each restaurant was last left on, so returning to a card
  /// resumes where it was. Bounded, because this outlives every search: it used
  /// to accumulate an entry per place seen for the life of the process.
  static final LinkedHashMap<String, int> _lastViewedIndices = LinkedHashMap();
  static const int _lastViewedLimit = 200;

  final Restaurant restaurant;
  final VoidCallback onPhotoTap;
  final int ranking;
  final double? currentLat;
  final double? currentLng;

  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onPhotoTap,
    required this.ranking,
    this.currentLat,
    this.currentLng,
  });

  @override
  State<RestaurantCard> createState() => _RestaurantCardState();
}

class _RestaurantCardState extends State<RestaurantCard> {
  late final PageController _pageController;

  /// A notifier rather than state, so paging through a restaurant's photos
  /// repaints the four dots underneath them instead of rebuilding the card —
  /// the header images, the rating row, the address, all of it.
  late final ValueNotifier<int> _photoIndex;

  @override
  void initState() {
    super.initState();
    final initial =
        RestaurantCard._lastViewedIndices[widget.restaurant.id] ?? 0;
    _photoIndex = ValueNotifier<int>(initial);
    _pageController = PageController(initialPage: initial);
  }

  @override
  void dispose() {
    final remembered = RestaurantCard._lastViewedIndices;
    remembered[widget.restaurant.id] = _photoIndex.value;
    while (remembered.length > RestaurantCard._lastViewedLimit) {
      remembered.remove(remembered.keys.first);
    }
    _photoIndex.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // Modified method to handle place details and directions
  void _openInGoogleMapsByPlaceId(BuildContext context, String placeId) async {
    // Construct the query using the restaurant's name and address
    final query = Uri.encodeComponent(
        '${widget.restaurant.name}, ${widget.restaurant.location.formattedAddress}');
    String nativeMapsUrl = 'comgooglemaps://?q=$query';

    // Try to open in native Maps app first
    if (await canLaunchUrlString(nativeMapsUrl)) {
      await launchUrlString(nativeMapsUrl);
    } else {
      // Fallback to browser using place ID if native app isn't installed
      final webMapsUrl =
          'https://www.google.com/maps/place/?q=place_id:$placeId';

      if (await canLaunchUrlString(webMapsUrl)) {
        await launchUrlString(webMapsUrl, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    }
  }

  void _getDirections(BuildContext context) async {
    if (widget.currentLat != null && widget.currentLng != null) {
      try {
        // Calculate straight-line distance for travel mode decision
        final distance = widget.restaurant.location.calculateDistance(
            widget.currentLat!,
            widget.currentLng!,
            widget.restaurant.location.latitude,
            widget.restaurant.location.longitude);

        // Choose travel mode based on distance
        final travelMode = distance <= 1 ? 'walking' : 'driving';

        final origin = '${widget.currentLat},${widget.currentLng}';

        // Launch in Google Maps with the destination address
        final mapsUrl = 'https://www.google.com/maps/dir/?api=1'
            '&origin=$origin'
            '&destination=${Uri.encodeComponent(widget.restaurant.location.formattedAddress)}'
            '&travelmode=$travelMode'
            '&dir_action=navigate';

        if (await canLaunchUrlString(mapsUrl)) {
          await launchUrlString(mapsUrl, mode: LaunchMode.externalApplication);
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Maps')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error getting directions: ${e.toString()}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo section
          if (widget.restaurant.photoRefs.isNotEmpty)
            Stack(
              children: [
                SizedBox(
                  height: 240,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.restaurant.photoRefs.length,
                    // PageView.builder builds the neighbouring page as you
                    // swipe, and PlacePhoto fetches on build, so the next photo
                    // is already on its way. The old explicit prefetch pulled
                    // every remaining photo the moment the card was touched.
                    onPageChanged: (index) => _photoIndex.value = index,
                    itemBuilder: (context, index) {
                      return Hero(
                        tag: 'restaurant_photo_${widget.restaurant.id}_$index',
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          child: PlacePhoto(
                            photoRef: widget.restaurant.photoRefs[index],
                            height: 240,
                            width: double.infinity,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _photoIndex,
                    builder: (context, current, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          widget.restaurant.photoRefs.length, (index) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: current == index ? 12 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: current == index ? Colors.white : Colors.grey,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),

          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fixed header content
                    GestureDetector(
                      onTap: () => _openInGoogleMapsByPlaceId(
                          context, widget.restaurant.placeId),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.restaurant.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              softWrap: true,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                          // Nested inside the "open in Google Maps" gesture on
                          // purpose: its own tap recogniser is deeper in the
                          // tree, so clearing a marker wins the gesture arena
                          // and does not also launch Maps.
                          PlaceStatusIcon(
                            placeId: widget.restaurant.placeId,
                            size: 22,
                            showListLabel: true,
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              widget.ranking.toString(),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Rating and Review Count
                    Row(
                      children: [
                        Text(
                          widget.restaurant.priceLevel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(width: 16),
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < widget.restaurant.rating.floor()
                                  ? Icons.star
                                  : index < widget.restaurant.rating
                                      ? Icons.star_half
                                      : Icons.star_outline,
                              color: Colors.amber,
                              size: 20,
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.restaurant.rating.toStringAsFixed(1)} (${widget.restaurant.reviewCount})',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Restaurant Types. Resolved once when the restaurant was
                    // parsed (see Restaurant.cuisineLabel) rather than twice
                    // per build off a freshly allocated keyword set.
                    Wrap(
                      spacing: 4,
                      runSpacing: 0,
                      children: [
                        if (widget.restaurant.cuisineLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.restaurant.cuisineLabel!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Description
                    if (widget.restaurant.description.isNotEmpty) ...[
                      Text(
                        widget.restaurant.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Address section
                    GestureDetector(
                      onTap: () => _getDirections(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Single row for location icon and distance
                          if (widget.currentLat != null &&
                              widget.currentLng != null) ...[
                            Row(
                              children: [
                                const Icon(Icons.place,
                                    color: Colors.black, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  'Distance: approx. ${widget.restaurant.location.formatDistance(widget.currentLat!, widget.currentLng!)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            widget.restaurant.location.formattedAddress,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.blue,
                                  decorationThickness: 1,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
