import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/restaurant.dart';
import '../services/restaurant_service.dart';
import '../widgets/restaurant_card.dart';
import '../widgets/restaurant_photo_viewer.dart';
import '../widgets/full_screen_photo.dart';

class RestaurantListScreen extends StatefulWidget {
  const RestaurantListScreen({super.key});

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  final RestaurantService _restaurantService = RestaurantService();
  List<Restaurant>? _restaurants;
  String? _error;
  bool _isLoading = true;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadRestaurants() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Request location permission
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requestedPermission = await Geolocator.requestPermission();
        if (requestedPermission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print('dBug/restaurant_list: Got location: ${position.latitude}, ${position.longitude}');

      // Fetch restaurants
      final rawRestaurants = await _restaurantService.getNearbyRestaurants(
        position.latitude,
        position.longitude,
        300.0,
      );
      
      final restaurants = rawRestaurants
          .map((place) => Restaurant.fromJson(place))
          .toList()
        ..sort((a, b) {
          final scoreA = a.calculateWilsonScore(a.rating, a.reviewCount);
          final scoreB = b.calculateWilsonScore(b.rating, b.reviewCount);
          return scoreB.compareTo(scoreA);
        });
      
      if (mounted) {
        setState(() {
          _restaurants = restaurants;
          _isLoading = false;
        });
      }

    } catch (e) {
      print('dBug/restaurant_list: Error loading restaurants: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showPhotoViewer(Restaurant restaurant) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestaurantPhotoViewer(
          restaurant: restaurant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Error loading restaurants:\n$_error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadRestaurants,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_restaurants?.isEmpty ?? true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'No restaurants found nearby',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadRestaurants,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Filter Buttons Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  // TODO: Handle all types
                },
                child: Text(
                  'All Types',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  // TODO: Handle open now
                },
                child: Text(
                  'Open Now',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  // TODO: Handle price range
                },
                child: Text(
                  '\$-\$\$\$\$',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
        
        // Restaurant Cards
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _restaurants!.length,
            onPageChanged: (index) {
              setState(() {
              });
            },
            itemBuilder: (context, index) {
              final restaurant = _restaurants![index];
              return Column(
                children: [
                  if (index > 0)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.keyboard_arrow_up, color: Colors.grey),
                    ),
                  
                  Expanded(
                    child: RestaurantCard(
                      restaurant: restaurant,
                      onPhotoTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => RestaurantPhotoViewer(
                              restaurant: restaurant,
                              initialIndex: 0,
                            ),
                          ),
                        );
                      },
                      ranking: index + 1,
                    ),
                  ),
                  
                  if (index < _restaurants!.length - 1)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
} 