import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../models/restaurant.dart';
import '../theme/app_spacing.dart';
import 'place_photo.dart';
import 'place_status_icon.dart';
import 'rank_badge.dart';
import 'rating_row.dart';
import 'tonal_chip.dart';

class RestaurantCard extends StatefulWidget {
  /// Which photo each restaurant was last left on, so returning to a card
  /// resumes where it was. Bounded, because this outlives every search: it used
  /// to accumulate an entry per place seen for the life of the process.
  static final LinkedHashMap<String, int> _lastViewedIndices = LinkedHashMap();
  static const int _lastViewedLimit = 200;

  final Restaurant restaurant;

  /// Opens the full-screen gallery on the photo that was tapped.
  ///
  /// This was a `VoidCallback` that nothing ever called — the card declared it,
  /// the list screen passed one that pushed [RestaurantPhotoViewer], and no
  /// code path in between invoked it, so the gallery was unreachable. It takes
  /// an index now because the gallery it opens can start anywhere, and opening
  /// on the first photo when the fifth was tapped is its own bug.
  final void Function(int photoIndex) onPhotoTap;

  final int ranking;
  final double? currentLat;
  final double? currentLng;

  /// Swiping the card sideways goes back to the list.
  ///
  /// Deliberately not wired to the photo header: that is a horizontal pager in
  /// its own right, and stealing its drags would cost you the ability to look
  /// through a restaurant's pictures.
  final VoidCallback? onSwipeBack;

  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onPhotoTap,
    required this.ranking,
    this.currentLat,
    this.currentLng,
    this.onSwipeBack,
  });

  @override
  State<RestaurantCard> createState() => _RestaurantCardState();
}

class _RestaurantCardState extends State<RestaurantCard> {
  static const double _photoHeight = 260;

  late final PageController _pageController;

  /// Horizontal distance travelled in the current back-swipe.
  double _dragX = 0;

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

  /// Either direction goes back — the card is a detour off the list, not a
  /// position in it, so there is no "forward" for a left swipe to mean.
  ///
  /// Accepts both a long slow drag and a quick flick; requiring one or the
  /// other is how a gesture ends up feeling broken for half its users.
  void _handleSwipeBack(DragEndDetails details) {
    final onSwipeBack = widget.onSwipeBack;
    if (onSwipeBack == null) return;

    final flicked = (details.primaryVelocity ?? 0).abs() > 300;
    if (_dragX.abs() > 60 || flicked) onSwipeBack();
  }

  @override
  Widget build(BuildContext context) {
    // Clipping comes from the shared CardTheme, so the photo's top corners are
    // rounded without a ClipRRect of its own. The old card had a bespoke
    // asymmetric radius — 24 at the top, 16 at the bottom — which read as a
    // drawing mistake rather than a decision.
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.restaurant.photoRefs.isNotEmpty) _buildPhotoHeader(),
          Flexible(
            child: GestureDetector(
              // Only the body carries the back-swipe. The photo header above
              // keeps its own horizontal pager.
              onHorizontalDragStart: (_) => _dragX = 0,
              onHorizontalDragUpdate: (d) => _dragX += d.delta.dx,
              onHorizontalDragEnd: _handleSwipeBack,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: _buildBody(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoHeader() {
    return Stack(
      children: [
        SizedBox(
          height: _photoHeight,
          width: double.infinity,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.restaurant.photoRefs.length,
            // PageView.builder builds the neighbouring page as you swipe, and
            // PlacePhoto fetches on build, so the next photo is already on its
            // way. The old explicit prefetch pulled every remaining photo the
            // moment the card was touched.
            onPageChanged: (index) => _photoIndex.value = index,
            itemBuilder: (context, index) {
              return GestureDetector(
                // A tap opens the gallery; the PageView keeps the horizontal
                // drag, so the two do not compete.
                onTap: () => widget.onPhotoTap(index),
                child: Hero(
                  tag: 'restaurant_photo_${widget.restaurant.id}_$index',
                  child: PlacePhoto(
                    photoRef: widget.restaurant.photoRefs[index],
                    height: _photoHeight,
                    width: double.infinity,
                    // The card opens on the first photo; the rest are only
                    // reached by swiping, so they wait behind every other
                    // place's one picture.
                    priority: index == 0,
                  ),
                ),
              );
            },
          ),
        ),

        // A scrim only where the dots sit. Photographs of food are frequently
        // pale at the bottom of the frame, and white dots on a white plate are
        // no dots at all.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 72,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.38),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          top: AppSpacing.md,
          right: AppSpacing.md,
          child: RankBadge.overlay(rank: widget.ranking),
        ),

        if (widget.restaurant.photoRefs.length > 1)
          Positioned(
            bottom: AppSpacing.md,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: _photoIndex,
                builder: (context, current, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.restaurant.photoRefs.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs - 1),
                      width: current == index ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: current == index
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.55),
                        borderRadius: AppRadius.pillAll,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final restaurant = widget.restaurant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () =>
              _openInGoogleMapsByPlaceId(context, restaurant.placeId),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  restaurant.name,
                  style: theme.textTheme.titleLarge,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
              // Nested inside the "open in Google Maps" gesture on purpose: its
              // own tap recogniser is deeper in the tree, so clearing a marker
              // wins the gesture arena and does not also launch Maps.
              PlaceStatusIcon(
                placeId: restaurant.placeId,
                size: 22,
                showListLabel: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        Row(
          children: [
            RatingRow(
              rating: restaurant.rating,
              reviewCount: restaurant.reviewCount,
              iconSize: 18,
              style: theme.textTheme.bodyMedium,
            ),
            if (restaurant.priceLevel.isNotEmpty) ...[
              const MetaDot(),
              Text(
                restaurant.priceLevel,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),

        // Restaurant types. Resolved once when the restaurant was parsed (see
        // Restaurant.cuisineLabel) rather than twice per build off a freshly
        // allocated keyword set.
        if (restaurant.cuisineLabel != null) ...[
          const SizedBox(height: AppSpacing.md),
          TonalChip(label: restaurant.cuisineLabel!),
        ],

        if (restaurant.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            restaurant.description,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],

        const SizedBox(height: AppSpacing.lg),
        _buildDirections(context),
      ],
    );
  }

  /// The address, as something that looks like it does something.
  ///
  /// It was blue underlined text — the visual language of a 1998 hyperlink, on
  /// a control that opens turn-by-turn navigation.
  Widget _buildDirections(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasPosition = widget.currentLat != null && widget.currentLng != null;

    return GestureDetector(
      onTap: () => _getDirections(context),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.directions_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasPosition)
                    Text(
                      'approx. ${widget.restaurant.location.formatDistance(widget.currentLat!, widget.currentLng!)} away',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                  if (hasPosition) const SizedBox(height: AppSpacing.xxs),
                  Text(
                    widget.restaurant.location.formattedAddress,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
