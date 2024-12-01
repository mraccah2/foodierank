import '../services/proxy_service.dart';
import 'dart:core';
import '../models/activity_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/location.dart';
import '../models/photo_details.dart';
import 'dart:convert';

class PlacesService {
  final Ref ref;
  final Map<String, Map<String, double>> _destinationCoordinatesCache = {};

  PlacesService(this.ref);

  Future<Map<String, double>?> getDestinationCoordinates(String destination) async {
    if (_destinationCoordinatesCache.containsKey(destination)) {
      print('dBug/places_service: Using cached coordinates for $destination');
      return _destinationCoordinatesCache[destination];
    }

    try {
      final coordinates = await _getCoordinatesFromAddress(destination);
      if (coordinates != null) {
        _destinationCoordinatesCache[destination] = {
          'lat': coordinates['lat'],
          'lng': coordinates['lng'],
        };
        print('dBug/places_service: Cached coordinates for $destination: ${coordinates['lat']}, ${coordinates['lng']}');
        return _destinationCoordinatesCache[destination];
      }
    } catch (e) {
      print('dBug/places_service: Error getting coordinates for $destination: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> fetchPlaceDetails(String query, double? latitude, double? longitude, {
    String? address, 
    String? destination,
    String? category,
    String? existingDescription,
    ActivityItem? activityItem,
    String? nearLocation
  }) async {
    try {
      if (activityItem?.hasGooglePlacesData == true) {
        return {};
      }

      Map<String, dynamic> searchParams = {};
      
      // Priority 1: Use specific address if available
      if (address?.isNotEmpty == true) {
        final coordinates = await _getCoordinatesFromAddress(address!);
        if (coordinates != null) {
          searchParams['location'] = '${coordinates['lat']},${coordinates['lng']}';
          searchParams['radius'] = '5000';  // Smaller radius for specific address
        }
      }
      
      // Priority 2: Use nearLocation if available
      if (searchParams['location'] == null && nearLocation?.isNotEmpty == true) {
        final coordinates = await _getCoordinatesFromAddress(nearLocation!);
        if (coordinates != null) {
          searchParams['location'] = '${coordinates['lat']},${coordinates['lng']}';
          searchParams['radius'] = '10000';
        }
      }
      
      // Priority 3: Use destination for location bias
      if (searchParams['location'] == null && destination?.isNotEmpty == true) {
        final coordinates = await getDestinationCoordinates(destination!);
        if (coordinates != null) {
          searchParams['location'] = '${coordinates['lat']},${coordinates['lng']}';
          searchParams['radius'] = '15000';  // Larger radius for city-level search
          print('dBug/places_service: Using destination coordinates for location bias');
        }
      }
      
      // Priority 4: Use provided coordinates as last resort
      if (searchParams['location'] == null && latitude != null && longitude != null) {
        searchParams['location'] = '$latitude,$longitude';
        searchParams['radius'] = '10000';
      }

      // Add destination context to query if we don't have specific coordinates
      if (searchParams['location'] == null && destination?.isNotEmpty == true) {
        searchParams['query'] = '$query in $destination';
      } else {
        searchParams['query'] = query;
      }

      final result = await _searchAndFetchDetails(
        searchParams['query'] ?? query,
        searchParams: Map<String, String>.from(searchParams),
        existingDescription: existingDescription,
        destination: destination
      );

      return result;
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, dynamic>?> _getCoordinatesFromAddress(String address) async {
    try {
      final geocodeData = await ProxyService.get('geocode', 'json', {
        'address': address,
      });

      if (geocodeData['results']?.isNotEmpty == true) {
        final location = geocodeData['results'][0]['geometry']['location'];
        return {
          'lat': location['lat'],
          'lng': location['lng'],
        };
      }
    } catch (e) {
      // Silent catch - removed debug print
    }
    return null;
  }

  Future<Map<String, dynamic>> _searchAndFetchDetails(
    String query,
    {
      Map<String, String>? searchParams,
      String? existingDescription,
      String? destination
    }) async {
    try {
      const fieldMask = 'places.displayName.text,places.formattedAddress,'
                       'places.location,places.photos,places.rating,'
                       'places.userRatingCount,places.types,'
                       'places.editorialSummary.text,'
                       'places.priceLevel,'
                       'places.businessStatus,'
                       'places.reviews';

      // Parse location coordinates for locationBias
      double? latitude, longitude;
      if (searchParams?['location'] != null) {
        final coords = searchParams!['location']!.split(',');
        latitude = double.parse(coords[0]);
        longitude = double.parse(coords[1]);
      }

      // Combine query with address if available
      String textQuery = query;
      if (searchParams?['address']?.isNotEmpty == true) {
        textQuery = '$query, ${searchParams!['address']}';
      }
      print('dBug/places_service: Using text query: $textQuery');

      // Construct the search request with new API format
      final params = {
        'textQuery': textQuery,
        'languageCode': 'en',
        'maxResultCount': 1,
        if (latitude != null && longitude != null)
          'locationBias': {
            'circle': {
              'center': {
                'latitude': latitude,
                'longitude': longitude
              },
              'radius': double.parse(searchParams?['radius'] ?? '5000')
            }
          }
      };

      print('dBug/places_service: Sending search request with params: ${json.encode(params)}');

      final data = await ProxyService.placesApiGet(
        'places:searchText',
        params,
        fieldMask: fieldMask,
      );

      if (data['places']?.isNotEmpty == true) {
        final place = data['places'][0];
        print('dBug/places_service: Found place: ${place['displayName']?['text']}');
        
        final result = {
          'name': place['displayName']?['text'],
          'address': place['formattedAddress'],
          'latitude': place['location']?['latitude'],
          'longitude': place['location']?['longitude'],
          'rating': place['rating'],
          'reviews': place['userRatingCount'],
          'photos': place['photos']?.map((photo) => {
            'name': photo['name'],
            'photoUri': null
          })?.toList() ?? [],
          'description': place['editorialSummary']?['text'],
          'priceLevel': place['priceLevel'],
          'types': place['types'],
          'businessStatus': place['businessStatus'],
          'userReviews': place['reviews'],
        };
        
        print('dBug/places_service: Processed place details with types: ${result['types']}');
        return result;
      } else {
        print('dBug/places_service: No places found for query: $textQuery');
      }
    } catch (e) {
      print('dBug/places_service: Error in _searchAndFetchDetails: $e');
    }
    return {};
  }

  Future<ActivityItem> enrichActivityWithPlaceDetails(
    ActivityItem activity, {
    String? destination,
    Location? destinationLocation,
  }) async {
    // Skip enrichment for meal or dining categories
    if (activity.category?.toLowerCase() == 'meal' || 
        activity.category?.toLowerCase() == 'dining') {
      return activity;
    }

    try {
      final placeDetails = await fetchPlaceDetails(
        activity.title ?? '',
        activity.location?.latitude ?? destinationLocation?.latitude,
        activity.location?.longitude ?? destinationLocation?.longitude,
        address: activity.location?.address,
        destination: destination,
        category: activity.category,
        existingDescription: activity.description,
        activityItem: activity,
        nearLocation: activity.location?.address,
      );

      if (placeDetails.isNotEmpty) {
        final types = placeDetails['types'] as List<dynamic>?;
        final derivedCategory = _deriveCategoryFromTypes(types);
        
        print('dBug/places_service: Types from place details: $types');
        print('dBug/places_service: Derived category: $derivedCategory');
        
        // Convert price level to integer
        int? priceLevel;
        if (placeDetails['priceLevel'] != null) {
          switch(placeDetails['priceLevel'].toString().toUpperCase()) {
            case 'PRICE_LEVEL_FREE':
              priceLevel = 0;
              break;
            case 'PRICE_LEVEL_INEXPENSIVE':
              priceLevel = 1;
              break;
            case 'PRICE_LEVEL_MODERATE':
              priceLevel = 2;
              break;
            case 'PRICE_LEVEL_EXPENSIVE':
              priceLevel = 3;
              break;
            case 'PRICE_LEVEL_VERY_EXPENSIVE':
              priceLevel = 4;
              break;
            default:
              // Try to parse if it's already a number
              priceLevel = int.tryParse(placeDetails['priceLevel'].toString());
          }
        }
        
        print('dBug/places_service: Converting price level from ${placeDetails['priceLevel']} to $priceLevel');

        final enrichedActivity = ActivityItem(
          id: activity.id,
          title: activity.title,
          description: placeDetails['description'] ?? activity.description,
          duration: activity.duration,
          startTime: activity.startTime,
          endTime: activity.endTime,
          activitySource: activity.activitySource,
          category: derivedCategory ?? activity.category,
          location: Location(
            name: placeDetails['name'],
            address: placeDetails['address'],
            latitude: placeDetails['latitude'],
            longitude: placeDetails['longitude'],
          ),
          rating: placeDetails['rating']?.toDouble(),
          reviews: placeDetails['reviews'],
          photoDetails: (placeDetails['photos'] as List<dynamic>?)
              ?.map((photo) => PhotoDetails(
                    name: photo['name'] as String?,
                    photoUri: photo['photoUri'] as String?,
                  ))
              .toList(),
          priceLevel: priceLevel,  // Use converted price level
          hasGooglePlacesData: true,
          selected: activity.selected,
          notInterested: activity.notInterested,
          isRecommendation: activity.isRecommendation,
          importance: activity.importance,
          recommendedDuration: activity.recommendedDuration,
          newlyAdded: activity.newlyAdded,
          conflictInStartTime: activity.conflictInStartTime,
        );
        
        print('dBug/places_service: Final category set: ${enrichedActivity.category}');
        return enrichedActivity;
      }
    } catch (e, stack) {
      print('dBug/places_service: Error enriching activity: $e');
      print('dBug/places_service: Stack trace: $stack');
    }

    return activity;
  }

  List<PhotoDetails> _convertToPhotoDetails(List<dynamic>? photos) {
    if (photos == null || photos.isEmpty) return [];
    
    return photos.map((photo) => PhotoDetails(
      name: photo,
      photoUri: null,
    )).toList();
  }

  // Implement the category mapping method
  String? _deriveCategoryFromTypes(List<dynamic>? types) {
    print('dBug/places_service: Attempting to derive category from types: $types');
    if (types == null || types.isEmpty) return null;

    // Define priority mapping of Google Places types to your categories
    const typeToCategory = {
      'restaurant': 'restaurant',
      'food': 'restaurant',
      'cafe': 'cafe',
      'bar': 'bar',
      'museum': 'museum',
      'art_gallery': 'museum',
      'park': 'park',
      'amusement_park': 'park',
      'tourist_attraction': 'attraction',
      'church': 'religious_site',
      'mosque': 'religious_site',
      'temple': 'religious_site',
      'shopping_mall': 'shopping',
      'store': 'shopping',
      'shopping': 'shopping',
      'beach': 'beach',
      'natural_feature': 'nature',
      'point_of_interest': 'attraction',
      'landmark': 'attraction',
    };

    // Look for the first matching type in order of priority
    for (final type in types) {
      final category = typeToCategory[type];
      if (category != null) {
        return category;
      }
    }

    // Add debug print for the result
    final result = typeToCategory[types.firstWhere(
      (type) => typeToCategory.containsKey(type),
      orElse: () => null
    )];
    print('dBug/places_service: Derived category result: $result');
    return result;
  }
}

