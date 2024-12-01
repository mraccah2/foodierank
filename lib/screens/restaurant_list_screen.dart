import 'dart:async';
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
  final TextEditingController _customTypeController = TextEditingController();
  String? _selectedDay;
  TimeOfDay? _selectedTime;
  double? _currentLat;
  double? _currentLng;

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

      // Get current position with better accuracy and timeout settings
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          // Fallback to last known position if getting current position times out
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) return lastKnown;
          throw TimeoutException('Could not get location');
        },
      );

      _currentLat = position.latitude;
      _currentLng = position.longitude;

      // Fetch restaurants
      final rawRestaurants = await _restaurantService.getNearbyRestaurants(
        position.latitude,
        position.longitude,
        priceLevel: _selectedPriceLevel,
        cuisineType: _selectedType,
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
                    'Select Cuisine Type',
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
    final now = DateTime.now();
    // Create temporary variables for selection
    String? tempDay = _selectedDay ?? _getWeekday(now.weekday);
    TimeOfDay? tempTime = _selectedTime ?? TimeOfDay.fromDateTime(now);

    // Generate list of times in 30-minute increments (12-hour format)
    final times = List.generate(24, (index) {
      final hour = (index ~/ 2) + 1;  // 1-12
      final minute = (index % 2) * 30;
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    });

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool isAm = (tempTime?.hour ?? 0) < 12;
            String timeString = tempTime != null 
                ? '${tempTime!.hourOfPeriod}:${tempTime!.minute.toString().padLeft(2, '0')}'
                : '12:00';

            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Opening Time',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Day selector
                      PopupMenuButton<String>(
                        initialValue: tempDay,
                        onSelected: (day) => setState(() => tempDay = day),
                        child: Chip(
                          label: Text(tempDay ?? 'Day'),
                          padding: const EdgeInsets.all(8),
                        ),
                        itemBuilder: (context) => [
                          'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
                        ].map((day) => PopupMenuItem(
                          value: day,
                          child: Text(day),
                        )).toList(),
                      ),
                      const SizedBox(width: 8),
                      // Time selector
                      PopupMenuButton<String>(
                        initialValue: timeString,
                        onSelected: (time) {
                          final parts = time.split(':');
                          final hour = int.parse(parts[0]);
                          final minute = int.parse(parts[1]);
                          setState(() {
                            tempTime = TimeOfDay(
                              hour: isAm ? hour : hour + 12,
                              minute: minute,
                            );
                          });
                        },
                        child: Chip(
                          label: Text(timeString),
                          padding: const EdgeInsets.all(8),
                        ),
                        itemBuilder: (context) {
                          return <PopupMenuEntry<String>>[
                            PopupMenuItem(
                              enabled: false,  // Header is not selectable
                              child: GridView.count(
                                shrinkWrap: true,
                                crossAxisCount: 3,  // Show in 3 columns
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 2.5,  // Adjust for better button proportions
                                children: times.map((time) => 
                                  InkWell(
                                    onTap: () {
                                      Navigator.pop(context, time);  // Return selected time
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
                          ];
                        },
                      ),
                      const SizedBox(width: 8),
                      // AM/PM selector
                      PopupMenuButton<bool>(
                        initialValue: isAm,
                        onSelected: (value) {
                          setState(() {
                            if (tempTime != null) {
                              final hour = tempTime!.hour % 12;
                              tempTime = TimeOfDay(
                                hour: value ? hour : hour + 12,
                                minute: tempTime!.minute,
                              );
                            }
                          });
                        },
                        child: Chip(
                          label: Text(isAm ? 'AM' : 'PM'),
                          padding: const EdgeInsets.all(8),
                        ),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: true,
                            child: Text('AM'),
                          ),
                          const PopupMenuItem(
                            value: false,
                            child: Text('PM'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedDay = tempDay;
                            _selectedTime = tempTime;
                          });
                          Navigator.pop(context);
                          _loadRestaurants();
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
      side: const BorderSide(
        color: Colors.black,
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
                    color: Colors.black,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _showOpenTimeDialog,
                style: buttonStyle,
                child: Text(
                  _selectedTime != null 
                    ? '$_selectedDay ${_selectedTime!.format(context)}'
                    : 'Open Now',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.black,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _showPriceFilter,
                style: buttonStyle,
                child: Text(
                  _selectedPriceLevel ?? '\$-\$\$\$\$',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.black,
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
                      currentLat: _currentLat,
                      currentLng: _currentLng,
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