import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import '../services/proxy_service.dart';

class RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onPhotoTap;
  final int ranking;

  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onPhotoTap,
    required this.ranking,
  });

  @override
  Widget build(BuildContext context) {
    // Get the first photo reference if available
    String? photoRef;
    if (restaurant.photoRefs.isNotEmpty) {
      photoRef = restaurant.photoRefs.first;
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
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
                    child: FutureBuilder<String>(
                      future: ProxyService.getPlacePhoto(photoRef, 800, 450),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          return Image.network(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 240,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.error_outline, size: 40),
                              );
                            },
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                      style: Theme.of(context).textTheme.titleMedium,
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
                      style: Theme.of(context).textTheme.bodyLarge,
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
                    return Chip(
                      label: Text(
                        type.replaceAll('_', ' ').toLowerCase(),
                        style: const TextStyle(fontSize: 11),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      labelPadding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Description
                if (restaurant.description.isNotEmpty) ...[
                  Text(
                    restaurant.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                ],
                // Address
                Text(
                  restaurant.address,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 
