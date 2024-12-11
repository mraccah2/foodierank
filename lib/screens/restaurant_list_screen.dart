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
  final bool _showOpenOnly = true;  // Default to showing only open restaurants
  String? _searchStatus;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchVisible = false;
  final FocusNode _searchFocusNode = FocusNode();
  static const int _lowResultsThreshold = 3;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchQuery = _searchController.text;  // Update query without setState
    });
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
    _searchController.dispose();
    _searchFocusNode.dispose();
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
        _searchStatus = null;  // Reset search status
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
        searchQuery: _searchQuery,
        onSearchUpdate: (count, type, radius) {
          if (mounted && count < _lowResultsThreshold && radius >= RestaurantService.maxRadius) {
            setState(() {
              _searchStatus = 'Found $count restaurants matching "$_searchQuery" nearby and open now.';
            });
          }
        },
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
      if (mounted) {
        setState(() {
          _error = 'Unable to load restaurant data. Please try again.';
          _isLoading = false;
          _searchStatus = null;  // Clear search status on error
        });
      }
    } finally {
      _isLoadingData = false;
    }
  }

  void _loadFromCache() async {
    final rawRestaurants = RestaurantService.instance.cachedRestaurants;
    if (rawRestaurants != null && rawRestaurants.isNotEmpty) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );

        if (!mounted) return;

        // Check if we need to refresh the data
        if (RestaurantService.instance.shouldRefreshData(
          position.latitude,
          position.longitude
        )) {
          _initializeAndLoad();
          return;
        }

        final restaurants = rawRestaurants
            .map((place) => Restaurant.fromJson(place))
            .toList();

        setState(() {
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          _restaurants = restaurants;
          _isLoading = false;
        });
        _sortRestaurants();
      } catch (e) {
        // Even if location fails, still show restaurants
        if (mounted) {
          final restaurants = rawRestaurants
              .map((place) => Restaurant.fromJson(place))
              .toList();
              
          setState(() {
            _restaurants = restaurants;
            _isLoading = false;
          });
          _sortRestaurants();
        }
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

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
    });
    
    if (_isSearchVisible) {
      // Add a micro-delay to ensure the TextField is rendered
      Future.delayed(const Duration(milliseconds: 50), () {
        FocusScope.of(context).requestFocus(_searchFocusNode);
      });
    } else {
      _searchController.clear();
      _searchQuery = '';
      _initializeAndLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset(
          'assets/logo.png'
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (_searchStatus != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _searchStatus!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Helper function to get the appropriate message
    String getErrorMessage() {
      if (_searchQuery.isNotEmpty) {
        return "There are no restaurants currently open around here that match your search.";
      } else if (_selectedType == 'All' && _selectedPriceLevel == null) {
        return "Couldn't find any restaurants currently open nearby. Please check back later";
      } else if (_selectedType != 'All' && _selectedPriceLevel != null) {
        return "Couldn't find any ${_selectedType!.toLowerCase()} restaurants with price level $_selectedPriceLevel currently open nearby";
      } else if (_selectedType != 'All') {
        return "Couldn't find any ${_selectedType!.toLowerCase()} restaurants currently open nearby";
      } else {
        return "Couldn't find any $_selectedPriceLevel restaurants currently open nearby";
      }
    }

    if (_error != null) {
      // Consider search query in default search check
      bool isDefaultSearch = _selectedType == 'All' && _selectedPriceLevel == null && _searchQuery.isEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                getErrorMessage(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (!isDefaultSearch) {
                    setState(() {
                      _selectedPriceLevel = null;
                      _selectedType = 'All';
                    });
                  }
                  _initializeAndLoad();
                },
                child: const Text('Go back'),  // Always show "Go back"
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
                getErrorMessage(),
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
      padding: const EdgeInsets.symmetric(horizontal: 8),  // Reduce horizontal padding
      side: const BorderSide(
        color: Colors.black,
        width: 1,
      ),
      minimumSize: const Size(0, 28),  // Only fix the height
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return RefreshIndicator(
      onRefresh: _initializeAndLoad,
      child: Column(
        children: [
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Filter Buttons Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Search button with dynamic background
                      ElevatedButton(
                        onPressed: _toggleSearch,
                        style: buttonStyle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Icon(
                            Icons.search,
                            color: _isSearchVisible ? Colors.blue[900] : Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                      // Type filter (always visible now)
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
                
                // Search Bar (only visible when search is active)
                if (_isSearchVisible) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.black,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            textAlignVertical: TextAlignVertical.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.black,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search for...',
                              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                                fontSize: 14,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? InkWell(
                                      onTap: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _isSearchVisible = false;  // Hide search bar
                                        });
                                        _initializeAndLoad();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.clear,
                                          color: Colors.grey,
                                          size: 16,
                                        ),
                                      ),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onSubmitted: (value) async {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              
                              try {
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
                                  searchQuery: value,
                                  onSearchUpdate: (count, type, radius) {
                                    if (mounted && count < _lowResultsThreshold && radius >= RestaurantService.maxRadius) {
                                      setState(() {
                                        _searchStatus = 'Found $count restaurants matching "$_searchQuery" nearby and open now.';
                                      });
                                    }
                                  },
                                );
                                
                                setState(() {
                                  _restaurants = rawRestaurants.map((r) => Restaurant.fromJson(r)).toList();
                                  _currentLat = position.latitude;
                                  _currentLng = position.longitude;
                                  _isLoading = false;
                                });
                                _sortRestaurants();
                              } catch (e) {
                                setState(() {
                                  _error = e.toString();
                                  _isLoading = false;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
                      const SizedBox(height: 5.0),  // Keep top padding
                      
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