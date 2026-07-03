import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../services/restaurant_service.dart';

class RestaurantCard extends StatefulWidget {
  static final Map<String, int> _lastViewedIndices = {};

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
  late int _currentPhotoIndex;
  bool _hasPreloadedPhotos = false;

  @override
  void initState() {
    super.initState();
    _currentPhotoIndex =
        RestaurantCard._lastViewedIndices[widget.restaurant.id] ?? 0;
    _pageController = PageController(initialPage: _currentPhotoIndex);
  }

  @override
  void dispose() {
    RestaurantCard._lastViewedIndices[widget.restaurant.id] =
        _currentPhotoIndex;
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

  Widget _buildPhoto(String photoRef) {
    final cachedPhoto = RestaurantService.instance.getCachedPhoto(photoRef);
    if (cachedPhoto != null) {
      return Image(
        image: MemoryImage(cachedPhoto),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 240,
      );
    }
    // Fallback to loading if somehow not cached
    return FutureBuilder<ImageProvider>(
      future: _getPhotoUrl(photoRef),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
            child: Icon(Icons.error_outline, size: 40),
          );
        }
        return Image(
          image: snapshot.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 240,
        );
      },
    );
  }

  // Add this method to _RestaurantCardState class
  String? _getDefaultCuisineByLocation(String country) {
    // Map of countries to their primary cuisine
    // Using the same cuisine keywords as in _findPrimaryCuisine
    final Map<String, String> countryCuisineMap = {
      'Afghanistan': 'afghan',
      'Argentina': 'argentinian',
      'Australia': 'australian',
      'Austria': 'austrian',
      'Belgium': 'belgian',
      'Brazil': 'brazilian',
      'China': 'chinese',
      'Colombia': 'colombian',
      'Croatia': 'croatian',
      'Cuba': 'cuban',
      'Czech Republic': 'czech',
      'Denmark': 'danish',
      'Ethiopia': 'ethiopian',
      'Philippines': 'filipino',
      'Finland': 'finnish',
      'France': 'french',
      'Georgia': 'georgian',
      'Germany': 'german',
      'Greece': 'greek',
      'Hungary': 'hungarian',
      'India': 'indian',
      'Indonesia': 'indonesian',
      'Ireland': 'irish',
      'Israel': 'israeli',
      'Italy': 'italian',
      'Jamaica': 'jamaican',
      'Japan': 'japanese',
      'Korea': 'korean',
      'Lebanon': 'lebanese',
      'Malaysia': 'malaysian',
      'Mexico': 'mexican',
      'Morocco': 'moroccan',
      'Nepal': 'nepalese',
      'Nigeria': 'nigerian',
      'Norway': 'norwegian',
      'Pakistan': 'pakistani',
      'Peru': 'peruvian',
      'Iran': 'persian',
      'Poland': 'polish',
      'Portugal': 'portuguese',
      'Romania': 'romanian',
      'Russia': 'russian',
      'Singapore': 'singaporean',
      'South Africa': 'south_african',
      'Spain': 'spanish',
      'Sweden': 'swedish',
      'Switzerland': 'swiss',
      'Taiwan': 'taiwanese',
      'Thailand': 'thai',
      'Turkey': 'turkish',
      'Ukraine': 'ukrainian',
      'Uruguay': 'uruguayan',
      'Venezuela': 'venezuelan',
      'Vietnam': 'vietnamese',
      'Wales': 'welsh'
    };

    final defaultCuisine = countryCuisineMap[country];
    return defaultCuisine;
  }

  // Modify the _findPrimaryCuisine method to use the default cuisine as fallback
  String? _findPrimaryCuisine(List<String> types) {
    // Common cuisine keywords that appear in Google Places types
    final cuisineKeywords = {
      'afghani',
      'african',
      'american',
      'arabic',
      'argentinian',
      'asian',
      'australian',
      'austrian',
      'bbq',
      'barbeque',
      'belgian',
      'brazilian',
      'british',
      'caribbean',
      'chinese',
      'colombian',
      'croatian',
      'cuban',
      'czech',
      'danish',
      'ethiopian',
      'filipino',
      'finnish',
      'french',
      'georgian',
      'german',
      'greek',
      'hungarian',
      'indian',
      'indonesian',
      'irish',
      'israeli',
      'italian',
      'jamaican',
      'japanese',
      'korean',
      'latin',
      'lebanese',
      'malaysian',
      'malay',
      'mediterranean',
      'mexican',
      'middle_eastern',
      'moroccan',
      'nepalese',
      'nigerian',
      'norwegian',
      'pakistani',
      'peruvian',
      'persian',
      'pizza',
      'polish',
      'portuguese',
      'romanian',
      'russian',
      'scandinavian',
      'scottish',
      'seafood',
      'singaporean',
      'south_african',
      'sushi',
      'spanish',
      'swedish',
      'swiss',
      'taiwanese',
      'thai',
      'turkish',
      'ukrainian',
      'uruguayan',
      'vegetarian',
      'venezuelan',
      'vietnamese',
      'welsh'
    };

    // First pass: check for compound types (e.g., "vegetarian_restaurant")
    for (var type in types) {
      final normalizedType = type.toLowerCase();
      // Extract the first part of compound types (before _restaurant, _food, etc.)
      final baseCuisine = normalizedType.split('_').first;
      if (cuisineKeywords.contains(baseCuisine)) {
        return baseCuisine;
      }
    }

    // Second pass: direct match with cuisine keywords
    for (var type in types) {
      final normalizedType = type.toLowerCase();
      if (cuisineKeywords.contains(normalizedType)) {
        return type;
      }
    }

    // If no cuisine type found, try to get default cuisine based on country
    final defaultCuisine =
        _getDefaultCuisineByLocation(widget.restaurant.location.country);
    if (defaultCuisine != null) {
      return defaultCuisine;
    }

    return null;
  }

  // Add this helper method to _RestaurantCardState
  String _formatCuisineDisplay(String cuisine) {
    return cuisine
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
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
                    onPageChanged: (index) {
                      setState(() {
                        _currentPhotoIndex = index;
                      });

                      // Prefetch remaining photos on first interaction
                      if (!_hasPreloadedPhotos) {
                        _hasPreloadedPhotos = true;
                        // Get all photo refs except the ones we've already loaded
                        final remainingPhotos = widget.restaurant.photoRefs
                            .where((ref) =>
                                RestaurantService.instance
                                    .getCachedPhoto(ref) ==
                                null)
                            .toList();

                        if (remainingPhotos.isNotEmpty) {
                          // Prefetch in the background
                          RestaurantService.instance
                              .prefetchHeaderPhotos(remainingPhotos);
                        }
                      }
                    },
                    itemBuilder: (context, index) {
                      return Hero(
                        tag: 'restaurant_photo_${widget.restaurant.id}_$index',
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          child:
                              _buildPhoto(widget.restaurant.photoRefs[index]),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.restaurant.photoRefs.length,
                        (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPhotoIndex == index ? 12 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPhotoIndex == index
                              ? Colors.white
                              : Colors.grey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
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

                    // Restaurant Types
                    Wrap(
                      spacing: 4,
                      runSpacing: 0,
                      children: [
                        // Try to find primary cuisine
                        if (_findPrimaryCuisine(widget.restaurant.types) !=
                            null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatCuisineDisplay(_findPrimaryCuisine(
                                  widget.restaurant.types)!),
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

  Future<ImageProvider> _getPhotoUrl(String photoRef) async {
    final cachedPhoto = RestaurantService.instance.getCachedPhoto(photoRef);
    if (cachedPhoto != null) {
      return MemoryImage(cachedPhoto);
    }
    // If not in cache, fetch and cache it
    await RestaurantService.instance.prefetchHeaderPhotos([photoRef]);
    return MemoryImage(RestaurantService.instance.getCachedPhoto(photoRef)!);
  }
}
