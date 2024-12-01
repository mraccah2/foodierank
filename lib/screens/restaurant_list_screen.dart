import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/restaurant.dart';
import '../services/restaurant_service.dart';
import '../widgets/restaurant_card.dart';
import '../widgets/restaurant_photo_viewer.dart';

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
  String? _selectedPriceLevel;
  String? _selectedType;
  TextEditingController _customTypeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _customTypeController.dispose();
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
        priceLevel: _selectedPriceLevel,
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

  void _showPriceFilter() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Price Range',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['\$', '\$\$', '\$\$\$', '\$\$\$\$'].map((price) {
                  return ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedPriceLevel = price;
                      });
                      Navigator.pop(context);
                      _loadRestaurants();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedPriceLevel == price 
                          ? Theme.of(context).colorScheme.primary 
                          : null,
                    ),
                    child: Text(price),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showTypeFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Cuisine Type',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      controller: controller,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 2.5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: RestaurantService.cuisineTypes.length,
                      itemBuilder: (context, index) {
                        final type = RestaurantService.cuisineTypes[index];
                        return ElevatedButton(
                          onPressed: () {
                            if (type == 'Other') {
                              _showCustomTypeDialog();
                            } else {
                              setState(() {
                                _selectedType = type;
                              });
                              Navigator.pop(context);
                              _loadRestaurants();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedType == type
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          child: Text(type),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showCustomTypeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Cuisine Type'),
          content: TextField(
            controller: _customTypeController,
            decoration: const InputDecoration(
              hintText: 'Enter cuisine type...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (_customTypeController.text.isNotEmpty) {
                  setState(() {
                    _selectedType = _customTypeController.text;
                  });
                  Navigator.pop(context);
                  Navigator.pop(context);
                  _loadRestaurants();
                }
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
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

    // Define button style outside the widget tree
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      side: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1,
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _showTypeFilter,
                style: buttonStyle,
                child: Text(
                  _selectedType ?? 'All Types',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  // TODO: Handle open now
                },
                style: buttonStyle,
                child: Text(
                  'Open Now',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _showPriceFilter,
                style: buttonStyle,
                child: Text(
                  _selectedPriceLevel ?? '\$-\$\$\$\$',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
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