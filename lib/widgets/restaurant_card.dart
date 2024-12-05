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
    required this.currentLat,
    required this.currentLng,
  });

  // Add method to launch Google Maps using Place ID
  void _openInGoogleMapsByPlaceId(BuildContext context, String placeId) async {
    final mapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=Google&query_place_id=$placeId').toString();

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
    // Get the first photo reference if available
    String? photoRef;
    if (restaurant.photoRefs.isNotEmpty) {
      photoRef = restaurant.photoRefs.first;
    }
    
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
          // Photo section with error handling
          if (photoRef != null)
            GestureDetector(
              onTap: onPhotoTap,
              child: Hero(
                tag: 'restaurant_photo_${restaurant.id}',
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 240,
                    child: Builder(
                      builder: (context) {
                        final cachedUrl = RestaurantService.instance.getCachedPhotoUrl(photoRef ?? '');
                        if (cachedUrl.isEmpty && photoRef != null) {
                          RestaurantService.instance.prefetchHeaderPhotos([photoRef]);
                        }
                        if (cachedUrl.isNotEmpty) {
                          return CachedNetworkImage(
                            imageUrl: cachedUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 240,
                            placeholder: (context, url) => const SizedBox.shrink(),
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(Icons.error_outline, size: 40),
                            ),
                          );
                        }
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Restaurant Name and Ranking
                Row(
                  children: [
                    // Restaurant name
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
                    // Ranking circle
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.amber,  // Changed to yellow/amber
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        ranking.toString(),
                        style: const TextStyle(
                          color: Colors.black,  // Changed to black for better contrast on yellow
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Rating and Review Count
                Row(
                  children: [
                    // Price Level
                    Text(
                      restaurant.priceLevel,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 16),  // Add more space between price and rating
                    
                    // Star Rating
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
                // Address
                GestureDetector(
                  onTap: () => _openInGoogleMapsByPlaceId(context, restaurant.placeId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (currentLat != null)
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Distance: approx. ${restaurant.location.formatDistance(currentLat!, currentLng!)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 20),  // Align with distance text
                        child: Text(
                          restaurant.location.formattedAddress,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            decoration: TextDecoration.underline,
                            color: Colors.blue,
                          ),
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
} 
