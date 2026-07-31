import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/restaurant.dart';
import '../models/search_context.dart';
import '../services/restaurant_service.dart';
import '../widgets/restaurant_card.dart';
import '../widgets/restaurant_photo_viewer.dart';
import '../widgets/minimal_restaurant_card.dart';
import '../widgets/restaurant_map_view.dart';
import '../widgets/location_picker_sheet.dart';
import '../widgets/time_picker_sheet.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/place_status_store.dart';
import 'account_screen.dart';

enum SortOption { rank, distance }

enum ViewMode { card, list, map }

class RestaurantListScreen extends StatefulWidget {
  const RestaurantListScreen({super.key});

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen>
    with WidgetsBindingObserver {
  List<Restaurant>? _restaurants;
  String? _error;
  bool _isLoading = true;
  final PageController _pageController = PageController();
  String? _selectedPriceLevel;
  String? _selectedType = 'All';
  final TextEditingController _customTypeController = TextEditingController();
  // The resolved centre of the current search (device GPS for "Near me", or the
  // picked place's coordinates). Distances are measured from here.
  double? _currentLat;
  double? _currentLng;
  // Where & when the search runs. Defaults to "Near me / Open now".
  SearchContext _searchContext = SearchContext.initial;
  SortOption _sortOption = SortOption.rank;
  bool _isScrolling = false;
  String? _searchStatus;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// When on, the list shows only places carrying a heart, star or flag.
  bool _taggedOnly = false;
  bool _isSearchVisible = false;
  final FocusNode _searchFocusNode = FocusNode();
  static const int _lowResultsThreshold = 3;
  DateTime? _lastRefreshTime;
  Position? _lastPosition;
  ViewMode _viewMode = ViewMode.list;
  bool _cardViewFromTap = false;
  int? _lastTappedIndex;
  final GlobalKey _scaffoldKey = GlobalKey();
  final Set<String> _selectedPriceLevels = {};

  /// How long a result set stays good enough to leave alone when the app comes
  /// back to the foreground.
  static const Duration _staleAfter = Duration(minutes: 45);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add lifecycle observer
    placeStatusStore.addListener(_onSavedPlacesChanged);
    _searchController.addListener(() {
      _searchQuery = _searchController.text; // Update query without setState
    });
    if (RestaurantService.instance.cachedRestaurants == null) {
      _initializeAndLoad();
    } else {
      _loadFromCache();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove lifecycle observer
    placeStatusStore.removeListener(_onSavedPlacesChanged);
    _pageController.dispose();
    _customTypeController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// The whole body used to be wrapped in an `AnimatedBuilder` on the saved-
  /// places store, so each of the three Firestore listeners rebuilt the header,
  /// the filters, the map and every card on every document change. The markers
  /// look after themselves — [PlaceStatusIcon] listens to the same store — so
  /// the list only needs rebuilding when marker membership decides what is in
  /// it.
  void _onSavedPlacesChanged() {
    if (!_taggedOnly) return;
    setState(_invalidateVisible);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkAndRefreshIfNeeded();
    }
  }

  Future<void> _checkAndRefreshIfNeeded() async {
    // Only the default "Near me / Open now" view auto-refreshes on resume. A
    // pinned custom location or time must stay put until the user changes it.
    if (!_searchContext.isDefault) return;
    if (_isLoadingData) return;

    // Comparing `DateTime.hour` meant that resuming at 3:01 after a 2:59 load
    // counted as stale and refetched everything — thirty-odd requests, two
    // minutes later. Elapsed time is what actually matters.
    final elapsed = _lastRefreshTime == null
        ? null
        : DateTime.now().difference(_lastRefreshTime!);
    final isStale = elapsed == null || elapsed >= _staleAfter;

    // A coarse fix is plenty to answer "have we moved 300m?", and far cheaper
    // than the best-accuracy GPS lock this used to request on every resume.
    final position =
        await LocationService.instance.current(accuracy: LocationAccuracy.low);
    if (!mounted) return;

    final hasMoved = position != null &&
        _lastPosition != null &&
        Geolocator.distanceBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              position.latitude,
              position.longitude,
            ) >
            300;

    if (!isStale && !hasMoved) return;
    if (position != null) _lastPosition = position;
    // Refresh underneath the results already on screen rather than replacing
    // them with a spinner.
    await _initializeAndLoad(silent: true);
  }

  bool _isLoadingData = false;

  /// Loads the current where/when/filter context.
  ///
  /// A [silent] load leaves whatever is on screen in place while it runs, and
  /// on failure leaves it there too — used for background refreshes and
  /// pull-to-refresh, where blanking the list to a spinner would be a downgrade
  /// from stale-but-readable.
  Future<void> _initializeAndLoad({bool silent = false}) async {
    if (_isLoadingData) return;
    _isLoadingData = true;

    try {
      setState(() {
        _isLoading = !silent;
        _error = null;
        _searchStatus = null;
      });

      // Resolve the search centre: the picked place for a custom location, or
      // the device's position for "Near me".
      final double lat;
      final double lng;
      if (_searchContext.isCustomLocation) {
        lat = _searchContext.lat!;
        lng = _searchContext.lng!;
      } else {
        final position = await LocationService.instance.current();
        if (!mounted) return;
        if (position == null) {
          throw StateError('No location available');
        }
        _lastPosition = position;
        lat = position.latitude;
        lng = position.longitude;
      }
      _lastRefreshTime = DateTime.now();

      _currentLat = lat;
      _currentLng = lng;

      final rawRestaurants = await RestaurantService.instance.fetchRestaurants(
        lat,
        lng,
        priceLevels: _getEffectivePriceLevels(),
        cuisineType: _selectedType,
        openNow: !_searchContext.isCustomTime,
        searchQuery: _searchQuery,
        targetDay: _searchContext.targetDay,
        targetMinutes: _searchContext.targetMinutes,
        contextKey: _searchContext.isDefault ? null : _searchContext.cacheKey,
        onSearchUpdate: (count, type, radius) {
          if (mounted &&
              count < _lowResultsThreshold &&
              radius >= RestaurantService.maxRadius) {
            setState(() {
              _searchStatus = _searchStatusMessage(count);
            });
          }
        },
      );

      if (!mounted) return;

      if (rawRestaurants.isEmpty) {
        setState(() {
          _error = _searchContext.isCustomTime
              ? 'No restaurants open ${_searchContext.timeDisplay.toLowerCase()} in this area'
              : 'No restaurants currently open in this area';
          _isLoading = false;
        });
        return;
      }

      final restaurants =
          rawRestaurants.map((place) => Restaurant.fromJson(place)).toList();

      restaurants
          .sort((a, b) => b.rankingScore.compareTo(a.rankingScore));

      for (var i = 0; i < restaurants.length; i++) {
        restaurants[i].rank = i + 1;
      }

      if (mounted) {
        setState(() {
          _restaurants = restaurants;
          _isLoading = false;
          _invalidateVisible();
        });
        _sortRestaurants();
      }
    } catch (e) {
      if (!mounted) return;
      // A background refresh that fails leaves what is already on screen alone:
      // those results are stale, not useless, and an error page would be a
      // downgrade from them.
      if (silent && _restaurants != null) return;
      setState(() {
        _error = 'Unable to load restaurant data. Please try again.';
        _isLoading = false;
        _searchStatus = null; // Clear search status on error
      });
    } finally {
      _isLoadingData = false;
    }
  }

  /// Renders the result set already in memory — restored from disk by the
  /// splash screen, or left by an earlier search — and only then works out
  /// whether it is still current.
  ///
  /// The order matters. This used to wait on a GPS fix and a staleness check
  /// before drawing anything, so a cold start with perfectly good cached
  /// results still opened on a spinner.
  Future<void> _loadFromCache() async {
    final rawRestaurants = RestaurantService.instance.cachedRestaurants;
    if (rawRestaurants == null || rawRestaurants.isEmpty) {
      return _initializeAndLoad();
    }

    final restaurants =
        rawRestaurants.map((place) => Restaurant.fromJson(place)).toList();

    // Whatever position we already have, without waiting for a fresh fix —
    // distances render from it, and it is only used to decide on a refresh.
    final known = LocationService.instance.lastKnown;
    if (!mounted) return;
    setState(() {
      _currentLat = known?.latitude;
      _currentLng = known?.longitude;
      _restaurants = restaurants;
      _isLoading = false;
      _invalidateVisible();
    });
    _sortRestaurants();

    final position = known ?? await LocationService.instance.current();
    if (!mounted || position == null) return;
    _lastPosition = position;
    _lastRefreshTime = DateTime.now();
    if (known == null) {
      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
      });
    }

    if (RestaurantService.instance.shouldRefreshData(
      position.latitude,
      position.longitude,
      priceLevels: _getEffectivePriceLevels(),
      cuisineType: _selectedType,
      openNow: !_searchContext.isCustomTime,
      searchQuery: _searchQuery,
      targetDay: _searchContext.targetDay,
      targetMinutes: _searchContext.targetMinutes,
      contextKey: _searchContext.isDefault ? null : _searchContext.cacheKey,
    )) {
      // Refresh underneath the results the user is already reading.
      unawaited(_initializeAndLoad(silent: true));
    }
  }

  void _showPriceRangeDialog() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            void updatePriceRange() {
              if (_selectedPriceLevels.isEmpty) return;

              // Get min and max selections
              List<String> levels = _selectedPriceLevels.toList()
                ..sort((a, b) => a.length.compareTo(b.length));

              // Find indices in the full price range
              final priceRange = ['\$', '\$\$', '\$\$\$', '\$\$\$\$'];
              int startIndex = priceRange.indexOf(levels.first);
              int endIndex = priceRange.indexOf(levels.last);

              // Add all levels between min and max
              setModalState(() {
                _selectedPriceLevels
                    .addAll(priceRange.sublist(startIndex, endIndex + 1));
              });
            }

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
                    children: ['\$', '\$\$', '\$\$\$', '\$\$\$\$'].map((price) {
                      final isSelected = _selectedPriceLevels.contains(price);
                      return InkWell(
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              _selectedPriceLevels.remove(price);
                            } else {
                              _selectedPriceLevels.add(price);
                            }
                            updatePriceRange(); // Auto-fill gaps after each selection
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
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
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _initializeAndLoad();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            );
          },
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
                              backgroundColor:
                                  isSelected ? Colors.grey : Colors.white,
                              side: const BorderSide(
                                  color: Colors.black, width: 1),
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
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
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

  /// Memoised so a rebuild does not re-filter. This getter is read once for
  /// `itemCount` and again inside every `itemBuilder` call, so recomputing it
  /// meant a `stateFor` lookup per restaurant per row — quadratic in the size
  /// of the list, on every frame that rebuilt it.
  List<Restaurant>? _visibleCache;

  void _invalidateVisible() => _visibleCache = null;

  /// The restaurants actually rendered.
  ///
  /// Ranking and sorting still run over the full set, so a place keeps the rank
  /// it earned among all results rather than being renumbered within the
  /// filtered subset.
  List<Restaurant> get _visibleRestaurants {
    final cached = _visibleCache;
    if (cached != null) return cached;

    final all = _restaurants ?? const <Restaurant>[];
    return _visibleCache = _taggedOnly
        ? all
            .where((r) =>
                placeStatusStore.stateFor(r.placeId).displayStatus != null)
            .toList()
        : all;
  }

  void _toggleTaggedFilter() {
    setState(() {
      _taggedOnly = !_taggedOnly;
      _invalidateVisible();
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  void _sortRestaurants() {
    if (_restaurants == null || _restaurants!.isEmpty) {
      return;
    }

    setState(() {
      _invalidateVisible();
      switch (_sortOption) {
        case SortOption.rank:
          _restaurants!
              .sort((a, b) => b.rankingScore.compareTo(a.rankingScore));

          // Assign ranks after sorting by rank
          for (var i = 0; i < _restaurants!.length; i++) {
            _restaurants![i].rank = i + 1;
          }
          break;

        case SortOption.distance:
          if (_currentLat != null && _currentLng != null) {
            _restaurants!.sort((a, b) {
              final distA = a.location.calculateDistance(_currentLat!,
                  _currentLng!, a.location.latitude, a.location.longitude);
              final distB = b.location.calculateDistance(_currentLat!,
                  _currentLng!, b.location.latitude, b.location.longitude);
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
      int nextPage = delta > 0
          ? currentPage - 1
          : // Move up one page
          currentPage + 1; // Move down one page

      // Ensure we don't go out of bounds
      nextPage = nextPage.clamp(0, _visibleRestaurants.length - 1);

      _pageController
          .animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          )
          .then((_) => _isScrolling = false);
    }
  }

  String _searchStatusMessage(int count) {
    final where = _searchContext.isCustomLocation
        ? 'near ${_searchContext.locationDisplay}'
        : 'nearby';
    final when = _searchContext.isCustomTime
        ? 'open ${_searchContext.timeDisplay.toLowerCase()}'
        : 'open now';
    if (_searchQuery.isNotEmpty) {
      return 'Found $count restaurants matching "$_searchQuery" $where and $when.';
    }
    return 'Found $count restaurants $where and $when.';
  }

  // --- Where & when context -------------------------------------------------

  Future<void> _openLocationPicker() async {
    // Seed autocomplete bias / map with the current centre (or a sane default).
    final biasLat = _currentLat ?? _lastPosition?.latitude ?? 37.7749;
    final biasLng = _currentLng ?? _lastPosition?.longitude ?? -122.4194;

    final result =
        await showLocationPicker(context, biasLat: biasLat, biasLng: biasLng);
    if (result == null || !mounted) return;

    setState(() {
      _searchContext = result.useCurrentLocation
          ? _searchContext.clearLocation()
          : _searchContext.withLocation(
              lat: result.place!.lat,
              lng: result.place!.lng,
              label: result.place!.label,
            );
    });
    _initializeAndLoad();
  }

  void _resetLocation() {
    setState(() => _searchContext = _searchContext.clearLocation());
    _initializeAndLoad();
  }

  Future<void> _openTimePicker() async {
    final result = await showTimeContextPicker(context,
        isCustom: _searchContext.isCustomTime);
    if (result == null || !mounted) return;

    setState(() {
      _searchContext = result.openNow
          ? _searchContext.clearTime()
          : _searchContext.withTime(
              day: result.day!,
              minutes: result.minutes!,
              label: result.label!,
            );
    });
    _initializeAndLoad();
  }

  void _resetTime() {
    setState(() => _searchContext = _searchContext.clearTime());
    _initializeAndLoad();
  }

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
    });

    if (_isSearchVisible) {
      // Add a micro-delay to ensure the TextField is rendered
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_searchFocusNode);
      });
    } else {
      _searchController.clear();
      _searchQuery = '';
      _initializeAndLoad();
    }
  }

  void _toggleViewMode() {
    setState(() {
      // From the map, this pill just returns you to the list.
      _viewMode = _viewMode == ViewMode.card ? ViewMode.list : ViewMode.card;
    });
  }

  void _toggleMapView() {
    setState(() {
      _viewMode = _viewMode == ViewMode.map ? ViewMode.list : ViewMode.map;
      _cardViewFromTap = false;
    });
  }

  /// Open a restaurant's card, the same way tapping a list row does — used by
  /// both the list and the map so a right-swipe still takes you back.
  void _showRestaurantCard(int index) {
    setState(() {
      _viewMode = ViewMode.card;
      _cardViewFromTap = true;
      _lastTappedIndex = index;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController.jumpToPage(index);
    });
  }

  void _handleHorizontalDrag(DragUpdateDetails details) {
    if (_cardViewFromTap && details.delta.dx > 20) {
      // Right swipe
      setState(() {
        _viewMode = ViewMode.list;
        _cardViewFromTap = false;
      });

      // Flash the card that was being viewed
      if (_lastTappedIndex != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = _scaffoldKey.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 300),
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset('assets/logo.png'),
        backgroundColor: Colors.grey[200],
        elevation: 0,
        actions: [
          // Signed-in users get their avatar; everyone else a neutral icon, so
          // the optional sign-in never reads as something the app requires.
          AnimatedBuilder(
            animation: AuthService.instance,
            builder: (context, _) {
              final photoUrl = AuthService.instance.photoUrl;
              return IconButton(
                tooltip: 'Saved places',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountScreen(),
                  ),
                ),
                icon: photoUrl != null
                    ? CircleAvatar(
                        radius: 13,
                        backgroundImage: NetworkImage(photoUrl),
                      )
                    : const Icon(Icons.account_circle_outlined),
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragUpdate: _cardViewFromTap ? _handleHorizontalDrag : null,
        // Only the card pager is driven by this drag — the map needs its own
        // pan/zoom gestures, and the list scrolls itself.
        onVerticalDragUpdate: _viewMode == ViewMode.card
            ? (details) => _handleScroll(details.delta.dy)
            : null,
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
      bool isDefaultSearch = _selectedType == 'All' &&
          _selectedPriceLevel == null &&
          _searchQuery.isEmpty;
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
                child: const Text('Go back'), // Always show "Go back"
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
      padding: const EdgeInsets.symmetric(
          horizontal: 8), // Reduce horizontal padding
      side: const BorderSide(
        color: Colors.black,
        width: 1,
      ),
      minimumSize: const Size(0, 28), // Only fix the height
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return RefreshIndicator(
      // The indicator is the progress; blanking the list to a spinner behind it
      // would be showing the same thing twice and losing the results meanwhile.
      onRefresh: () => _initializeAndLoad(silent: true),
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Type filter (always visible now)
                      ElevatedButton(
                        onPressed: _showTypeFilter,
                        style: buttonStyle,
                        child: Text(
                          _selectedType == 'All' ? 'All types' : _selectedType!,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.black,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _showPriceRangeDialog,
                        style: buttonStyle,
                        child: Text(
                          _getPriceLevelDisplay(),
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.black,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _sortOption == SortOption.rank
                                  ? Icons.star
                                  : Icons.directions_walk,
                              color: Colors.black,
                              size: 20,
                            ),
                            const SizedBox(width: 2),
                            Transform.rotate(
                              angle:
                                  _sortOption == SortOption.rank ? 0 : 3.14159,
                              child: const Icon(
                                Icons.sort,
                                color: Colors.black,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _toggleViewMode,
                        style: buttonStyle,
                        child: Icon(
                          _viewMode == ViewMode.card
                              ? Icons.view_list_sharp
                              : Icons
                                  .crop_portrait, // Changed from view_agenda to crop_portrait
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Where & when context row
                _buildContextRow(),

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
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.black,
                                      fontSize: 14,
                                    ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search for...',
                              hintStyle: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
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
                                          _isSearchVisible =
                                              false; // Hide search bar
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
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onSubmitted: (value) {
                              // The controller listener keeps _searchQuery in
                              // sync; run the search through the shared path so
                              // the current where/when context is honoured.
                              _searchQuery = value;
                              _initializeAndLoad();
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
              child: _viewMode == ViewMode.map
                  ? RestaurantMapView(
                      restaurants: _visibleRestaurants,
                      currentLat: _currentLat,
                      currentLng: _currentLng,
                      onRestaurantTap: _showRestaurantCard,
                    )
                  : _viewMode == ViewMode.card
                      ? PageView.builder(
                          controller: _pageController,
                          scrollDirection: Axis.vertical,
                          pageSnapping: true,
                          physics: const PageScrollPhysics(),
                          itemCount: _visibleRestaurants.length,
                          // No `onPageChanged` here on purpose: it used to hold
                          // an empty `setState`, which rebuilt the header, the
                          // filters and every card on each swipe. Nothing in
                          // this subtree reads the current page.
                          itemBuilder: (context, index) {
                            final restaurant = _visibleRestaurants[index];
                            return Column(
                              children: [
                                const SizedBox(height: 5.0), // Keep top padding

                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0)
                                        .copyWith(
                                      top: 8.0,
                                      bottom: 8.0,
                                    ),
                                    child: RestaurantCard(
                                      restaurant: restaurant,
                                      onPhotoTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                RestaurantPhotoViewer(
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

                                const SizedBox(
                                    height: 30.0), // Keep bottom padding
                              ],
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                              top: 3), // Added top padding
                          itemCount: _visibleRestaurants.length,
                          itemBuilder: (context, index) {
                            final restaurant = _visibleRestaurants[index];
                            return MinimalRestaurantCard(
                              restaurant: restaurant,
                              ranking: restaurant.rank ?? index + 1,
                              currentLat: _currentLat,
                              currentLng: _currentLng,
                              onTap: () => _showRestaurantCard(index),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  /// The "where & when" pills, bracketed by the search and map toggles. The
  /// pills stay collapsed to a single line to keep the header uncluttered;
  /// detail lives in the sheets.
  Widget _buildContextRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconPill(
          icon: Icons.search,
          active: _isSearchVisible,
          onTap: _toggleSearch,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: _contextPill(
            icon: Icons.place_outlined,
            label: _searchContext.locationDisplay,
            // Both filters are always applied — "Near me" and "Open now" are
            // the defaults, not the absence of a filter — so the pills read as
            // on from a cold start. Only a *customised* pill offers a clear.
            active: true,
            onTap: _openLocationPicker,
            onClear: _searchContext.isCustomLocation ? _resetLocation : null,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: _contextPill(
            icon: Icons.schedule,
            label: _searchContext.timeDisplay,
            active: true,
            onTap: _openTimePicker,
            onClear: _searchContext.isCustomTime ? _resetTime : null,
          ),
        ),
        const SizedBox(width: 8),
        _iconPill(
          icon: _taggedOnly ? Icons.flag : Icons.flag_outlined,
          active: _taggedOnly,
          onTap: _toggleTaggedFilter,
        ),
        const SizedBox(width: 8),
        _iconPill(
          icon: Icons.map_outlined,
          active: _viewMode == ViewMode.map,
          onTap: _toggleMapView,
        ),
      ],
    );
  }

  /// A round icon toggle sized to sit flush with [_contextPill].
  Widget _iconPill({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? Colors.blue[900] : Colors.black,
        ),
      ),
    );
  }

  Widget _contextPill({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.only(left: 12, right: onClear != null ? 6 : 12),
        height: 32,
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : Colors.black),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? Colors.white : Colors.black,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.close,
                      size: 16, color: active ? Colors.white : Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getPriceLevelDisplay() {
    if (_selectedPriceLevels.isEmpty) return '\$-\$\$\$\$';

    List<String> levels = _selectedPriceLevels.toList()
      ..sort((a, b) => a.length.compareTo(b.length));

    if (levels.length == 1) return levels.first;
    return '${levels.first}-${levels.last}';
  }

  List<String> _getEffectivePriceLevels() {
    // Map of dollar signs to API enum values
    final priceMap = {
      '\$': 'PRICE_LEVEL_INEXPENSIVE',
      '\$\$': 'PRICE_LEVEL_MODERATE',
      '\$\$\$': 'PRICE_LEVEL_EXPENSIVE',
      '\$\$\$\$': 'PRICE_LEVEL_VERY_EXPENSIVE',
    };

    if (_selectedPriceLevels.isEmpty) {
      // Return all price levels plus UNSPECIFIED
      return [
        'PRICE_LEVEL_UNSPECIFIED',
        'PRICE_LEVEL_INEXPENSIVE',
        'PRICE_LEVEL_MODERATE',
        'PRICE_LEVEL_EXPENSIVE',
        'PRICE_LEVEL_VERY_EXPENSIVE'
      ];
    }

    List<String> levels = _selectedPriceLevels.toList()
      ..sort((a, b) => a.length.compareTo(b.length));

    int startIndex = ['\$', '\$\$', '\$\$\$', '\$\$\$\$'].indexOf(levels.first);
    int endIndex = ['\$', '\$\$', '\$\$\$', '\$\$\$\$'].indexOf(levels.last);

    // Convert dollar signs to API enum values and include UNSPECIFIED
    return ['PRICE_LEVEL_UNSPECIFIED'] +
        ['\$', '\$\$', '\$\$\$', '\$\$\$\$']
            .sublist(startIndex, endIndex + 1)
            .map((level) => priceMap[level]!)
            .toList();
  }
}
