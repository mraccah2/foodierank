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
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  final RestaurantService _restaurantService = RestaurantService();
  List<Restaurant>? _restaurants;
  String? _error;
  bool _isLoading = true;
  final PageController _pageController = PageController();
  String? _selectedPriceLevel;
  String? _selectedType = 'All';
  final TextEditingController _customTypeController = TextEditingController();
  TimeOfDay? _selectedTime;
  double? _currentLat;
  double? _currentLng;
  SortOption _sortOption = SortOption.rank;

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

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      );

      _currentLat = position.latitude;
      _currentLng = position.longitude;

      // Use cached results if available and no filters are applied
      final bool noFilters = _selectedPriceLevel == null && 
                            (_selectedType == 'All' || _selectedType == null) && 
                            _selectedTime == null;

      final rawRestaurants = noFilters && _restaurantService.cachedRestaurants != null
          ? _restaurantService.cachedRestaurants!
          : await _restaurantService.getNearbyRestaurants(
              position.latitude,
              position.longitude,
              priceLevel: _selectedPriceLevel,
              cuisineType: _selectedType == 'All' ? null : _selectedType,
              openTime: _selectedTime,
            );

      final restaurants = rawRestaurants
          .map((place) => Restaurant.fromJson(place))
          .toList()
        ..sort((a, b) {
          final scoreA = a.calculateWilsonScore(a.rating, a.reviewCount);
          final scoreB = b.calculateWilsonScore(b.rating, b.reviewCount);
          return scoreB.compareTo(scoreA);
        });
      
      // Assign ranks based on Wilson score
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
                      setState(() => _selectedPriceLevel = price == 'All' ? null : price);
                      Navigator.pop(context);
                      _loadRestaurants();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.brown : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.brown),
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
                                _loadRestaurants();
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isSelected 
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.transparent,
                              side: const BorderSide(color: Colors.black, width: 1),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              type,
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

  void _showOpenTimeDialog() {
    // Use current time as initial selection if none set

    // Generate list of valid times (30-minute increments from current time until midnight)
    final currentTime = TimeOfDay.now();
    final times = <String>['Open Now']; // Add "Open Now" as the first option

    // Start from current hour/minute (rounded up to next 30 min increment)
    var hour = currentTime.hour;
    var minute = currentTime.minute >= 30 ? 0 : 30;
    if (currentTime.minute >= 30) {
      hour = (hour + 1) % 24;
    }

    // Add times until midnight
    while (hour < 24) {
      final hourStr = (hour % 12 == 0 ? 12 : hour % 12).toString().padLeft(2, '0');
      final minStr = minute.toString().padLeft(2, '0');
      final amPm = hour < 12 ? 'AM' : 'PM';
      times.add('$hourStr:$minStr $amPm');

      minute += 30;
      if (minute >= 60) {
        minute = 0;
        hour++;
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Time',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.5,
                  children: times.map((time) => 
                    InkWell(
                      onTap: () {
                        if (time == 'Open Now') {
                          setState(() => _selectedTime = null);
                        } else {
                          // Parse time string back to TimeOfDay
                          final parts = time.split(' ');
                          final timeParts = parts[0].split(':');
                          var hour = int.parse(timeParts[0]);
                          final minute = int.parse(timeParts[1]);
                          final amPm = parts[1];

                          if (amPm == 'PM' && hour != 12) hour += 12;
                          if (amPm == 'AM' && hour == 12) hour = 0;

                          setState(() {
                            _selectedTime = TimeOfDay(hour: hour, minute: minute);
                          });
                        }
                        Navigator.pop(context);
                        _loadRestaurants();
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(time),
                      ),
                    ),
                  ).toList(),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _selectedTime = null);
                  Navigator.pop(context);
                  _loadRestaurants();
                },
                child: const Text('Clear Filter'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getWeekday(int day) {
    switch (day) {
      case DateTime.monday: return 'Mon';
      case DateTime.tuesday: return 'Tue';
      case DateTime.wednesday: return 'Wed';
      case DateTime.thursday: return 'Thu';
      case DateTime.friday: return 'Fri';
      case DateTime.saturday: return 'Sat';
      case DateTime.sunday: return 'Sun';
      default: return 'Mon';
    }
  }

  void _sortRestaurants() {
    if (_restaurants == null) return;
    
    setState(() {
      switch (_sortOption) {
        case SortOption.rank:
          _restaurants!.sort((a, b) {
            final scoreA = a.calculateWilsonScore(a.rating, a.reviewCount);
            final scoreB = b.calculateWilsonScore(b.rating, b.reviewCount);
            return scoreB.compareTo(scoreA);
          });
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.grey[200],
        surfaceTintColor: Colors.grey[200],
        elevation: 0,
        title: Text(
          'Foodie Rank',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
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

    return Column(
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
                  _selectedType ?? 'All Types',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.black,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _showOpenTimeDialog,
                style: buttonStyle,
                child: Text(
                  _selectedTime != null 
                    ? _selectedTime!.format(context)
                    : 'Open Now',
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
                child: Icon(
                  _sortOption == SortOption.rank 
                    ? Icons.star_outline 
                    : Icons.route,
                  color: Colors.black,
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
              itemCount: _restaurants!.length,
              onPageChanged: (index) {
                setState(() {});
              },
              itemBuilder: (context, index) {
                final restaurant = _restaurants![index];
                return Column(
                  children: [
                    const SizedBox(height: 20.0),  // Top edge padding
                    
                    if (index > 0)
                      const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
                    
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0).copyWith(
                          top: 8.0,    // Space between up arrow and card
                          bottom: 8.0,  // Space between card and down arrow
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
                    
                    if (index < _restaurants!.length - 1)
                      const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                      
                    const SizedBox(height: 60.0),  // Bottom edge padding
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
} 