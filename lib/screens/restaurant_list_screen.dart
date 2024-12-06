import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/restaurant.dart';
import '../services/restaurant_service.dart';
import '../widgets/restaurant_card.dart';
import '../widgets/restaurant_photo_viewer.dart';

enum SortOption {
  rank,
  distance
}

class RestaurantListScreen extends StatefulWidget {
  const RestaurantListScreen({super.key});

  @override
  _RestaurantListScreenState createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  List<Restaurant>? _restaurants;
  String? _error;
  bool _isLoading = true;
  final PageController _pageController = PageController();
  String? _selectedPriceLevel;
  String? _selectedType = 'All';
  final TextEditingController _customTypeController = TextEditingController();
  double? _currentLat;
  double? _currentLng;
  SortOption _sortOption = SortOption.rank;
  bool _isScrolling = false;
  bool _showOpenOnly = true;  // Default to showing only open restaurants

  @override
  void initState() {
    super.initState();
    if (RestaurantService.instance.cachedRestaurants == null) {
      _initializeAndLoad();
    } else {
      _loadFromCache();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

  bool _isLoadingData = false;

  Future<void> _initializeAndLoad() async {
    if (_isLoadingData) return;
    _isLoadingData = true;
    
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      );

      if (!mounted) return;

      _currentLat = position.latitude;
      _currentLng = position.longitude;

      final rawRestaurants = await RestaurantService.instance.fetchRestaurants(
        position.latitude,
        position.longitude,
        priceLevel: _selectedPriceLevel,
        cuisineType: _selectedType,
        openNow: _showOpenOnly,
      );

      if (!mounted) return;

      if (rawRestaurants.isEmpty) {
        setState(() {
          _error = _showOpenOnly 
              ? 'No restaurants currently open in this area'
              : 'No restaurants found in this area';
          _isLoading = false;
        });
        return;
      }

      final restaurants = rawRestaurants
          .map((place) => Restaurant.fromJson(place))
          .toList();
      
      restaurants.sort((a, b) {
        final scoreA = a.calculateWilsonScore(a.rating, a.reviewCount);
        final scoreB = b.calculateWilsonScore(b.rating, b.reviewCount);
        return scoreB.compareTo(scoreA);
      });
      
      for (var i = 0; i < restaurants.length; i++) {
        restaurants[i].rank = i + 1;
      }
      
      if (mounted) {
        setState(() {
          _restaurants = restaurants;
          _isLoading = false;
        });
        _sortRestaurants();
      }

    } catch (e) {
      print('dBug/restaurant_list_screen: Exception - $e');
      if (mounted) {
        setState(() {
          _error = 'Unable to load restaurant data. Please try again.';
          _isLoading = false;
        });
      }
    } finally {
      _isLoadingData = false;
    }
  }

  void _loadFromCache() async {
    final rawRestaurants = RestaurantService.instance.cachedRestaurants;
    if (rawRestaurants != null && rawRestaurants.isNotEmpty) {
      // Get current position first
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );

        if (!mounted) return;

        setState(() {
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          _restaurants = rawRestaurants
              .map((place) => Restaurant.fromJson(place))
              .toList();
          _isLoading = false;
          _sortRestaurants();
        });
      } catch (e) {
        print('dBug/restaurant_list_screen: Location error in cache load - $e');
        // Still show restaurants even if location fails
        setState(() {
          _restaurants = rawRestaurants
              .map((place) => Restaurant.fromJson(place))
              .toList();
          _isLoading = false;
          _sortRestaurants();
        });
      }
    } else {
      _initializeAndLoad();
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

  void _showPriceRangeDialog() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Price Range',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['All', '\$', '\$\$', '\$\$\$', '\$\$\$\$'].map((price) {
                  final isSelected = _selectedPriceLevel == price || (price == 'All' && _selectedPriceLevel == null);
                  return InkWell(
                    onTap: () {
                      final newPrice = price == 'All' ? null : price;
                      setState(() => _selectedPriceLevel = newPrice);
                      Navigator.pop(context);
                      _initializeAndLoad();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.grey : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black),
                      ),
                      child: Text(
                        price,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
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
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Type',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: RestaurantService.cuisineTypes.map((type) {
                          final isSelected = _selectedType == type;
                          return OutlinedButton(
                            onPressed: () {
                              if (type == 'Other') {
                                _showCustomTypeDialog();
                              } else {
                                setState(() {
                                  _selectedType = type;
                                });
                                Navigator.pop(context);
                                _initializeAndLoad();
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isSelected 
                                  ? Colors.grey
                                  : Colors.white,
                              side: const BorderSide(color: Colors.black, width: 1),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              type == 'All' ? 'All types' : type,
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
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
          title: const Text('Search keyword:'),
          content: TextField(
            controller: _customTypeController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            // Only allow single word input
            onChanged: (value) {
              if (value.contains(' ')) {
                _customTypeController.text = value.split(' ')[0];
                _customTypeController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _customTypeController.text.length),
                );
              }
            },
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
                  _initializeAndLoad();
                }
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  void _sortRestaurants() {
    if (_restaurants == null || _restaurants!.isEmpty) {
      print('dBug/restaurant_list_screen: No restaurants to sort.');
      return;
    }
    
    setState(() {
      switch (_sortOption) {
        case SortOption.rank:
          _restaurants!.sort((a, b) {
            final scoreA = a.calculateWilsonScore(a.rating, a.reviewCount);
            final scoreB = b.calculateWilsonScore(b.rating, b.reviewCount);
            return scoreB.compareTo(scoreA);
          });
          
          // Assign ranks after sorting by rank
          for (var i = 0; i < _restaurants!.length; i++) {
            _restaurants![i].rank = i + 1;
          }
          break;
          
        case SortOption.distance:
          if (_currentLat != null && _currentLng != null) {
            _restaurants!.sort((a, b) {
              final distA = a.location.calculateDistance(_currentLat!, _currentLng!, 
                a.location.latitude, a.location.longitude);
              final distB = b.location.calculateDistance(_currentLat!, _currentLng!,
                b.location.latitude, b.location.longitude);
              return distA.compareTo(distB);
            });
          }
          break;
      }
      
      // Check if the PageController is attached before jumping
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      } else {
        print('dBug/restaurant_list_screen: PageController has no clients.');
      }
    });
  }

  void _handleScroll(double delta) {
    if (_isScrolling) return;
    
    if (delta.abs() > 20) {
      _isScrolling = true;
      int currentPage = _pageController.page!.round();
      int nextPage = delta > 0 ? 
          currentPage - 1 :  // Move up one page
          currentPage + 1;   // Move down one page
      
      // Ensure we don't go out of bounds
      nextPage = nextPage.clamp(0, _restaurants!.length - 1);
      
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) => _isScrolling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset(
          'assets/logo.png' // Adjust the height as needed
        ),
        backgroundColor: Colors.grey[200],
        elevation: 0,
      ),
      body: GestureDetector(
        onVerticalDragUpdate: (details) => _handleScroll(details.delta.dy),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
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
                onPressed: _initializeAndLoad,
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
                onPressed: _initializeAndLoad,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Define button style outside the widget tree
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      side: const BorderSide(
        color: Colors.black,
        width: 1,
      ),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return RefreshIndicator(
      onRefresh: _initializeAndLoad,
      child: Column(
        children: [
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _showTypeFilter,
                  style: buttonStyle,
                  child: Text(
                    _selectedType == 'All' ? 'All types' : _selectedType!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.black,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _showPriceRangeDialog,
                  style: buttonStyle,
                  child: Text(
                    _selectedPriceLevel ?? '\$-\$\$\$\$',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.black,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _sortOption = _sortOption == SortOption.rank 
                        ? SortOption.distance 
                        : SortOption.rank;
                      _sortRestaurants();
                    });
                  },
                  style: buttonStyle,
                  child: Text(
                    _sortOption == SortOption.rank ? 'Best first' : 'Closest first',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Restaurant Cards with padding
          Expanded(
            child: Container(
              color: Colors.grey[200],
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                pageSnapping: true,
                physics: const PageScrollPhysics(),
                itemCount: _restaurants!.length,
                onPageChanged: (index) {
                  setState(() {});
                },
                itemBuilder: (context, index) {
                  final restaurant = _restaurants![index];
                  return Column(
                    children: [
                      const SizedBox(height: 20.0),  // Keep top padding
                      
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0).copyWith(
                            top: 8.0,
                            bottom: 8.0,
                          ),
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
                            ranking: restaurant.rank ?? index + 1,
                            currentLat: _currentLat,
                            currentLng: _currentLng,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 30.0),  // Keep bottom padding
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
} 