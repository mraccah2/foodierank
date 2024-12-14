import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import '../services/restaurant_service.dart';

class MinimalRestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final int ranking;
  final double? currentLat;
  final double? currentLng;
  final VoidCallback onTap;

  const MinimalRestaurantCard({
    super.key,
    required this.restaurant,
    required this.ranking,
    this.currentLat,
    this.currentLng,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String distance = '';
    if (currentLat != null && currentLng != null) {
      distance = restaurant.location.formatDistance(currentLat!, currentLng!);
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // First column: Ranking Circle
              SizedBox(
                width: 36,
                child: Container(
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
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Second column: Restaurant details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Restaurant name
                      Text(
                        restaurant.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      // Metadata row
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            restaurant.priceLevel,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 14,
                                color: Colors.amber[700],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                restaurant.rating.toString(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          Text(
                            '(${restaurant.reviewCount})',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Builder(
                            builder: (context) {
                              final primaryCuisine = RestaurantService.instance.findPrimaryCuisine(
                                restaurant.types,
                                country: restaurant.location.country,
                              );
                              if (primaryCuisine != null) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    RestaurantService.instance.formatCuisineDisplay(primaryCuisine),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          if (distance.isNotEmpty)
                            Text(
                              distance,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Third column: Photo
              if (restaurant.photoRefs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: _buildPhoto(restaurant.photoRefs.first),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Add this helper method to build the photo
  Widget _buildPhoto(String photoRef) {
    final cachedPhoto = RestaurantService.instance.getCachedPhoto(photoRef);
    if (cachedPhoto != null) {
      return Image.memory(
        cachedPhoto,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
      );
    }
    return const Center(
      child: SizedBox(
        width: 60,
        height: 60,
        child: CircularProgressIndicator(),
      ),
    );
  }
} 