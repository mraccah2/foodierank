import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../services/restaurant_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class RestaurantCard extends StatelessWidget {
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

  // Modified method to handle place details and directions
  void _openInGoogleMapsByPlaceId(BuildContext context, String placeId, {bool forDirections = false}) async {
    String mapsUrl;
    
    if (forDirections && currentLat != null && currentLng != null) {
      // URL for directions from current location
      mapsUrl = 'https://www.google.com/maps/dir/?api=1'
          '&origin=${currentLat},${currentLng}'
          '&destination=place_id:$placeId'
          '&travelmode=driving';
    } else {
      // URL for place details
      mapsUrl = 'https://www.google.com/maps/place/?q=place_id:$placeId';
    }

    if (await canLaunchUrlString(mapsUrl)) {
      await launchUrlString(mapsUrl, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo section remains unchanged
          if (restaurant.photoRefs.isNotEmpty)
            GestureDetector(
              onTap: onPhotoTap,
              child: Hero(
                tag: 'restaurant_photo_${restaurant.id}',
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  child: FutureBuilder<String>(
                    future: _getPhotoUrl(restaurant.photoRefs.first),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Icon(Icons.error_outline, size: 40),
                        );
                      } else {
                        return CachedNetworkImage(
                          imageUrl: snapshot.data!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 240,
                          placeholder: (context, url) => const SizedBox.shrink(),
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(Icons.error_outline, size: 40),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Restaurant Name and Ranking with new tap behavior
                GestureDetector(
                  onTap: () => _openInGoogleMapsByPlaceId(context, restaurant.placeId),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          softWrap: true,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          ranking.toString(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Rating and Review Count
                Row(
                  children: [
                    Text(
                      restaurant.priceLevel,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 16),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < restaurant.rating.floor()
                              ? Icons.star
                              : index < restaurant.rating
                                  ? Icons.star_half
                                  : Icons.star_outline,
                          color: Colors.amber,
                          size: 20,
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${restaurant.rating.toStringAsFixed(1)} (${restaurant.reviewCount})',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Restaurant Types
                Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  children: restaurant.types
                      .take(3)
                      .map((type) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        type.replaceAll('_', ' ').toLowerCase(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Description
                if (restaurant.description.isNotEmpty) ...[
                  Text(
                    restaurant.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                ],

                // Address section with new tap behavior for directions
                GestureDetector(
                  onTap: () async {
                    if (currentLat != null && currentLng != null) {
                      final destLat = restaurant.location.latitude;
                      final destLng = restaurant.location.longitude;
                      
                      // Calculate distance in meters
                      final distance = restaurant.location.calculateDistance(
                        currentLat!, 
                        currentLng!, 
                        destLat, 
                        destLng
                      );
                      
                      // Choose travel mode based on distance
                      final travelMode = distance <= 500 ? 'walking' : 'driving';
                      
                      final mapsUrl = 'https://www.google.com/maps/dir/?api=1'
                          '&origin=${currentLat},${currentLng}'
                          '&destination=$destLat,$destLng'
                          '&travelmode=$travelMode';

                      if (await canLaunchUrlString(mapsUrl)) {
                        await launchUrlString(mapsUrl, mode: LaunchMode.externalApplication);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not open Google Maps')),
                        );
                      }
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Single row for location icon and distance
                      if (currentLat != null && currentLng != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.place, color: Colors.black, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              'Distance: approx. ${restaurant.location.formatDistance(currentLat!, currentLng!)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        restaurant.location.formattedAddress,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
        ],
      ),
    );
  }

  Future<String> _getPhotoUrl(String photoRef) async {
    // Check if the photo URL is already cached
    String cachedUrl = RestaurantService.instance.getCachedPhotoUrl(photoRef);
    if (cachedUrl.isEmpty) {
      // If not cached, prefetch and then check again
      await RestaurantService.instance.prefetchHeaderPhotos([photoRef]);
      cachedUrl = RestaurantService.instance.getCachedPhotoUrl(photoRef);
    }
    return cachedUrl;
  }
} 
