import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  static const String _keyLocationMode = 'location_mode'; // 'auto' or 'manual'
  static const String _keyManualLocation = 'manual_location';
  static const String _keyManualCity = 'manual_city';
  static const String _keyManualZip = 'manual_zip';
  
  /// Get user-specific cache key prefix
  static String _getUserCachePrefix() {
    try {
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user != null) {
        return 'user_${user.id}_';
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting user ID for cache prefix: $e');
      }
    }
    return 'guest_'; // Fallback for non-authenticated users
  }

  /// Get current location display string
  /// Returns manual location if set, otherwise device location
  /// Falls back to last known ZIP code from database if location fails
  /// Uses user-specific cache for faster loading
  static Future<String> getCurrentLocationDisplay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPrefix = _getUserCachePrefix();
      
      // First, check user-specific cache (fastest)
      final cachedLocation = prefs.getString('${userPrefix}cached_location');
      if (cachedLocation != null && cachedLocation.isNotEmpty) {
        if (kDebugMode) {
          print('[LocationService] Using cached location from browser: $cachedLocation');
        }
        return cachedLocation;
      }
      
      // Check user-specific manual location
      final mode = prefs.getString('${userPrefix}${_keyLocationMode}') ?? 
                   prefs.getString(_keyLocationMode) ?? 'auto';

      if (mode == 'manual') {
        // Use manually set location (user-specific first, then fallback)
        final manualLocation = prefs.getString('${userPrefix}${_keyManualLocation}') ??
                              prefs.getString(_keyManualLocation);
        if (manualLocation != null && manualLocation.isNotEmpty) {
          return manualLocation;
        }
      }
      
      // If logged in, check database for user's last known ZIP code
      try {
        final supa = Supabase.instance.client;
        final user = supa.auth.currentUser;
        if (user != null) {
          final result = await supa
              .from('users')
              .select('last_known_zip_code')
              .eq('id', user.id)
              .maybeSingle();
          
          final lastKnownZip = result?['last_known_zip_code'] as String?;
          if (lastKnownZip != null && lastKnownZip.isNotEmpty) {
            // Convert ZIP to city, state for display
            final cityState = await getCityStateFromZip(lastKnownZip);
            if (cityState != null) {
              // Cache it for faster future access
              await prefs.setString('${userPrefix}cached_location', cityState);
              if (kDebugMode) {
                print('[LocationService] Using logged-in user\'s location from database: $cityState');
              }
              return cityState;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[LocationService] Error getting user location from database: $e');
        }
        // Continue to fallback logic
      }

      // Use device location with 3-second timeout
      try {
        final position = await _getCurrentPosition().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            if (kDebugMode) {
              print('[LocationService] getCurrentLocationDisplay timed out after 3 seconds');
            }
            return null;
          },
        );
        
        if (position != null) {
          final cityName = await _getCityFromPosition(position);
          if (cityName != null) {
            // Cache the location for future use (user-specific)
            await prefs.setString('${userPrefix}cached_location', cityName);
            await prefs.setDouble('${userPrefix}cached_lat', position.latitude);
            await prefs.setDouble('${userPrefix}cached_lng', position.longitude);
            // Also save ZIP code to database
            final zip = await getZipFromPosition(position);
            if (zip != null) {
              await _saveLastKnownZipCode(zip);
              await prefs.setString('${userPrefix}cached_zip', zip);
            }
            return cityName;
          }
        }
      } on TimeoutException {
        if (kDebugMode) {
          print('[LocationService] Location request timed out, using fallback');
        }
      }

      // Try to use cached location (user-specific)
      final cached = prefs.getString('${userPrefix}cached_location');
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }

      // Fallback: Get last known ZIP code and convert to city, state
      final lastKnownZip = await _getLastKnownZipCodeFromDatabase();
      if (lastKnownZip != null) {
        final cityState = await getCityStateFromZip(lastKnownZip);
        if (cityState != null) {
          // Cache it for future use (user-specific)
          await prefs.setString('${userPrefix}cached_location', cityState);
          return cityState;
        }
      }

      return 'Location';
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting location: $e');
      }
      // Try cached location on error (user-specific)
      try {
        final prefs = await SharedPreferences.getInstance();
        final userPrefix = _getUserCachePrefix();
        final cached = prefs.getString('${userPrefix}cached_location');
        if (cached != null && cached.isNotEmpty) {
          return cached;
        }
        
        // Final fallback: last known ZIP from database
        final lastKnownZip = await _getLastKnownZipCodeFromDatabase();
        if (lastKnownZip != null) {
          final cityState = await getCityStateFromZip(lastKnownZip);
          if (cityState != null) {
            // Cache it for future use
            await prefs.setString('${userPrefix}cached_location', cityState);
            return cityState;
          }
        }
        
        return 'Location';
      } catch (_) {
        return 'Location';
      }
    }
  }

  /// Get current coordinates (latitude, longitude)
  /// Returns Map with 'lat' and 'lng' keys
  static Future<Map<String, double>?> getCurrentCoordinates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPrefix = _getUserCachePrefix();
      
      // First, try user-specific cached coordinates (fastest)
      final cachedLat = prefs.getDouble('${userPrefix}cached_lat');
      final cachedLng = prefs.getDouble('${userPrefix}cached_lng');
      if (cachedLat != null && cachedLng != null) {
        return {'lat': cachedLat, 'lng': cachedLng};
      }
      
      final mode = prefs.getString('${userPrefix}${_keyLocationMode}') ??
                   prefs.getString(_keyLocationMode) ?? 'auto';

      if (mode == 'manual') {
        // Use manually set coordinates (user-specific first, then fallback)
        final lat = prefs.getDouble('${userPrefix}manual_lat') ??
                   prefs.getDouble('manual_lat');
        final lng = prefs.getDouble('${userPrefix}manual_lng') ??
                   prefs.getDouble('manual_lng');
        if (lat != null && lng != null) {
          return {'lat': lat, 'lng': lng};
        }
      }

      // Use device location
      final position = await _getCurrentPosition();
      
      if (position != null) {
        // Cache coordinates (user-specific)
        await prefs.setDouble('${userPrefix}cached_lat', position.latitude);
        await prefs.setDouble('${userPrefix}cached_lng', position.longitude);
        return {
          'lat': position.latitude,
          'lng': position.longitude,
        };
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting coordinates: $e');
      }
      // Try cached coordinates on error (user-specific)
      try {
        final prefs = await SharedPreferences.getInstance();
        final userPrefix = _getUserCachePrefix();
        final cachedLat = prefs.getDouble('${userPrefix}cached_lat');
        final cachedLng = prefs.getDouble('${userPrefix}cached_lng');
        if (cachedLat != null && cachedLng != null) {
          return {'lat': cachedLat, 'lng': cachedLng};
        }
      } catch (_) {}
      return null;
    }
  }

  /// Calculate distance between two coordinates in miles
  static double calculateDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    // Use Geolocator's distance calculation (returns meters)
    final distanceInMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    // Convert to miles
    return distanceInMeters * 0.000621371;
  }

  /// Calculate distance between two ZIP codes in miles
  /// Returns null if either ZIP code is invalid or coordinates can't be found
  static Future<double?> calculateDistanceBetweenZipCodes({
    required String zip1,
    required String zip2,
  }) async {
    try {
      if (kDebugMode) {
        print('[LocationService] Calculating distance between ZIP codes: $zip1 -> $zip2');
      }
      
      // If ZIP codes are the same, distance is 0
      // Normalize ZIP codes (remove whitespace, ensure consistent format)
      final normalizedZip1 = zip1.trim();
      final normalizedZip2 = zip2.trim();
      
      if (normalizedZip1 == normalizedZip2) {
        if (kDebugMode) {
          print('[LocationService] ✅ Same ZIP codes ($normalizedZip1 == $normalizedZip2), distance = 0 miles');
        }
        return 0.0;
      }
      
      if (kDebugMode) {
        print('[LocationService] ZIP codes differ: "$normalizedZip1" != "$normalizedZip2"');
      }
      
      // Get coordinates for both ZIP codes using OpenStreetMap Nominatim API (works in web)
      double? lat1, lng1, lat2, lng2;
      
      // Get coordinates for ZIP1
      // Use ZIP code directly in query for more accurate geocoding
      try {
        final zip1Data = await _searchByZip(zip1);
        String searchQuery1;
        if (zip1Data != null && zip1Data['city'] != null && zip1Data['state'] != null) {
          // Include ZIP code in query to make it more specific and accurate
          searchQuery1 = '${zip1Data['city']}, ${zip1Data['state']} $zip1, USA';
        } else {
          // Fallback to ZIP code
          searchQuery1 = '$zip1, USA';
        }
        
        if (kDebugMode) {
          print('[LocationService] Geocoding ZIP1 ($zip1) with query: "$searchQuery1"');
        }
        
        final coords1 = await _geocodeWithNominatim(searchQuery1);
        if (coords1 != null) {
          lat1 = coords1['lat'];
          lng1 = coords1['lng'];
          if (kDebugMode) {
            print('[LocationService] ✅ Got coordinates for ZIP1 ($zip1): ($lat1, $lng1)');
          }
        } else {
          // Try with just ZIP code if city/state query failed
          if (kDebugMode) {
            print('[LocationService] ⚠️  City/state query failed, trying ZIP code directly');
          }
          final coords1Fallback = await _geocodeWithNominatim('$zip1, USA');
          if (coords1Fallback != null) {
            lat1 = coords1Fallback['lat'];
            lng1 = coords1Fallback['lng'];
            if (kDebugMode) {
              print('[LocationService] ✅ Got coordinates for ZIP1 ($zip1) via fallback: ($lat1, $lng1)');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[LocationService] ❌ Error geocoding ZIP1: $e');
        }
      }
      
      // Get coordinates for ZIP2
      // Use ZIP code directly in query for more accurate geocoding
      try {
        final zip2Data = await _searchByZip(zip2);
        String searchQuery2;
        if (zip2Data != null && zip2Data['city'] != null && zip2Data['state'] != null) {
          // Include ZIP code in query to make it more specific and accurate
          searchQuery2 = '${zip2Data['city']}, ${zip2Data['state']} $zip2, USA';
        } else {
          // Fallback to ZIP code
          searchQuery2 = '$zip2, USA';
        }
        
        if (kDebugMode) {
          print('[LocationService] Geocoding ZIP2 ($zip2) with query: "$searchQuery2"');
        }
        
        final coords2 = await _geocodeWithNominatim(searchQuery2);
        if (coords2 != null) {
          lat2 = coords2['lat'];
          lng2 = coords2['lng'];
          if (kDebugMode) {
            print('[LocationService] ✅ Got coordinates for ZIP2 ($zip2): ($lat2, $lng2)');
          }
        } else {
          // Try with just ZIP code if city/state query failed
          if (kDebugMode) {
            print('[LocationService] ⚠️  City/state query failed, trying ZIP code directly');
          }
          final coords2Fallback = await _geocodeWithNominatim('$zip2, USA');
          if (coords2Fallback != null) {
            lat2 = coords2Fallback['lat'];
            lng2 = coords2Fallback['lng'];
            if (kDebugMode) {
              print('[LocationService] ✅ Got coordinates for ZIP2 ($zip2) via fallback: ($lat2, $lng2)');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[LocationService] ❌ Error geocoding ZIP2: $e');
        }
      }

      if (lat1 == null || lng1 == null) {
        if (kDebugMode) {
          print('[LocationService] ❌ Could not get coordinates for ZIP code 1: $zip1');
        }
        return null;
      }
      
      if (lat2 == null || lng2 == null) {
        if (kDebugMode) {
          print('[LocationService] ❌ Could not get coordinates for ZIP code 2: $zip2');
        }
        return null;
      }

      if (kDebugMode) {
        print('[LocationService] Coordinates: ZIP1 ($zip1) = ($lat1, $lng1), ZIP2 ($zip2) = ($lat2, $lng2)');
      }

      // Calculate distance using coordinates
      // Verify coordinates are reasonable (lat: -90 to 90, lng: -180 to 180)
      if (lat1.abs() > 90 || lat2.abs() > 90 || lng1.abs() > 180 || lng2.abs() > 180) {
        if (kDebugMode) {
          print('[LocationService] ❌ Invalid coordinates detected!');
          print('[LocationService]    ZIP1 ($zip1): lat=$lat1, lng=$lng1');
          print('[LocationService]    ZIP2 ($zip2): lat=$lat2, lng=$lng2');
        }
        return null;
      }
      
      final distanceInMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
      
      if (kDebugMode) {
        print('[LocationService] Distance in meters: ${distanceInMeters.toStringAsFixed(2)}');
        print('[LocationService] Distance in kilometers: ${(distanceInMeters / 1000).toStringAsFixed(2)}');
      }
      
      // Convert to miles (1 meter = 0.000621371 miles)
      final distance = distanceInMeters * 0.000621371;
      
      if (kDebugMode) {
        print('[LocationService] ✅ Calculated distance: ${distance.toStringAsFixed(2)} miles');
        
        // Verify calculation: if distance seems wrong for nearby ZIPs, log warning
        if (zip1.length >= 2 && zip2.length >= 2 && zip1.substring(0, 2) == zip2.substring(0, 2)) {
          // Both ZIPs start with same 2 digits (likely same state/region)
          if (distance > 20) {
            print('[LocationService] ⚠️  WARNING: Distance seems unusually large for nearby ZIP codes');
            print('[LocationService]    ZIP1: $zip1, ZIP2: $zip2');
            print('[LocationService]    Expected: ~3-5 miles, Got: ${distance.toStringAsFixed(2)} miles');
            print('[LocationService]    This might indicate a geocoding issue - check coordinates above');
          }
        }
      }
      
      return distance;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] ❌ Error calculating distance between ZIP codes: $e');
        print('[LocationService] Stack trace: ${StackTrace.current}');
      }
      return null;
    }
  }

  /// Geocode an address using OpenStreetMap Nominatim API (works in web)
  /// Returns map with 'lat' and 'lng' keys, or null if geocoding fails
  static Future<Map<String, double>?> _geocodeWithNominatim(String query) async {
    try {
      // OpenStreetMap Nominatim API - free, no API key required, works in web
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=1');
      
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'SportsdugApp/1.0', // Required by Nominatim
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (data.isNotEmpty) {
          final result = data[0] as Map<String, dynamic>;
          final lat = double.tryParse(result['lat']?.toString() ?? '');
          final lng = double.tryParse(result['lon']?.toString() ?? '');
          
          if (lat != null && lng != null) {
            return {'lat': lat, 'lng': lng};
          }
        }
      }
      
      if (kDebugMode) {
        print('[LocationService] ⚠️  Nominatim geocoding returned no results for: $query');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] ❌ Error geocoding with Nominatim: $e');
      }
      return null;
    }
  }

  /// Save ZIP code to database as last known ZIP code
  static Future<void> _saveLastKnownZipCode(String zipCode) async {
    try {
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      
      if (user == null) {
        if (kDebugMode) {
          print('[LocationService] No authenticated user, cannot save ZIP code to database');
        }
        return;
      }

      await supa.from('users').update({
        'last_known_zip_code': zipCode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);

      if (kDebugMode) {
        print('[LocationService] ✅ Saved last known ZIP code to database: $zipCode');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] ⚠️  Failed to save ZIP code to database: $e');
      }
      // Don't throw - this is a non-critical operation
    }
  }

  /// Get last known ZIP code from database
  static Future<String?> _getLastKnownZipCodeFromDatabase() async {
    try {
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      
      if (user == null) {
        return null;
      }

      final result = await supa
          .from('users')
          .select('last_known_zip_code')
          .eq('id', user.id)
          .maybeSingle();

      final zipCode = result?['last_known_zip_code'] as String?;
      
      if (kDebugMode && zipCode != null) {
        print('[LocationService] Retrieved last known ZIP code from database: $zipCode');
      }
      
      return zipCode;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] ⚠️  Failed to get ZIP code from database: $e');
      }
      return null;
    }
  }

  /// Get current user's ZIP code (from device location or manual setting)
  /// Falls back to last known ZIP code from database if current location fails
  /// Has a 3-second timeout - if location doesn't load within 3 seconds, uses last known ZIP
  static Future<String?> getCurrentZipCode({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPrefix = _getUserCachePrefix();
      
      // First, check user-specific cache (fastest)
      final cachedZip = prefs.getString('${userPrefix}cached_zip');
      if (cachedZip != null && cachedZip.isNotEmpty) {
        if (kDebugMode) {
          print('[LocationService] Using cached ZIP from browser: $cachedZip');
        }
        return cachedZip;
      }
      
      // Check user-specific manual location
      final mode = prefs.getString('${userPrefix}${_keyLocationMode}') ??
                   prefs.getString(_keyLocationMode) ?? 'auto';

      if (mode == 'manual') {
        // Use manually set ZIP code (user-specific first, then fallback)
        final manualZip = prefs.getString('${userPrefix}${_keyManualZip}') ??
                         prefs.getString(_keyManualZip);
        if (manualZip != null && manualZip.isNotEmpty) {
          // Save to database as last known
          await _saveLastKnownZipCode(manualZip);
          // Cache it for faster future access
          await prefs.setString('${userPrefix}cached_zip', manualZip);
          return manualZip;
        }
      }
      
      // If logged in, check database for user's last known ZIP code
      try {
        final supa = Supabase.instance.client;
        final user = supa.auth.currentUser;
        if (user != null) {
          final result = await supa
              .from('users')
              .select('last_known_zip_code')
              .eq('id', user.id)
              .maybeSingle();
          
          final lastKnownZip = result?['last_known_zip_code'] as String?;
          if (lastKnownZip != null && lastKnownZip.isNotEmpty) {
            // Cache it for faster future access
            await prefs.setString('${userPrefix}cached_zip', lastKnownZip);
            if (kDebugMode) {
              print('[LocationService] Using logged-in user\'s ZIP from database: $lastKnownZip');
            }
            return lastKnownZip;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[LocationService] Error getting user ZIP from database: $e');
        }
        // Continue to fallback logic
      }

      // Use device location to get ZIP code with 3-second timeout
      try {
        final positionFuture = _getCurrentPosition();
        final position = await positionFuture.timeout(
          timeout,
          onTimeout: () {
            if (kDebugMode) {
              print('[LocationService] Location request timed out after ${timeout.inSeconds} seconds');
            }
            return null;
          },
        );
        
        if (position != null) {
          final zip = await getZipFromPosition(position);
          if (zip != null) {
            // Cache the ZIP code locally (user-specific)
            await prefs.setString('${userPrefix}cached_zip', zip);
            // Save to database as last known
            await _saveLastKnownZipCode(zip);
            return zip;
          }
        }
      } on TimeoutException {
        if (kDebugMode) {
          print('[LocationService] Location request timed out after ${timeout.inSeconds} seconds, using fallback');
        }
      } catch (e) {
        if (kDebugMode && e is! TimeoutException) {
          print('[LocationService] Error getting position: $e');
        }
        // Continue to fallback
      }

      // Try cached ZIP code from local storage (user-specific)
      final cachedZip2 = prefs.getString('${userPrefix}cached_zip');
      if (cachedZip2 != null && cachedZip2.isNotEmpty) {
        // Save to database as last known (in case it wasn't saved before)
        await _saveLastKnownZipCode(cachedZip2);
        return cachedZip2;
      }

      // Fallback: Get last known ZIP code from database
      final lastKnownZip = await _getLastKnownZipCodeFromDatabase();
      if (lastKnownZip != null && lastKnownZip.isNotEmpty) {
        if (kDebugMode) {
          print('[LocationService] Using last known ZIP code from database: $lastKnownZip');
        }
        // Cache it locally for future use (user-specific)
        await prefs.setString('${userPrefix}cached_zip', lastKnownZip);
        return lastKnownZip;
      }

      if (kDebugMode) {
        print('[LocationService] ⚠️  No ZIP code available from any source');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting current ZIP code: $e');
      }
      
      // Try cached ZIP on error (user-specific)
      try {
        final prefs = await SharedPreferences.getInstance();
        final userPrefix = _getUserCachePrefix();
        final cachedZip = prefs.getString('${userPrefix}cached_zip');
        if (cachedZip != null && cachedZip.isNotEmpty) {
          return cachedZip;
        }
        
        // Final fallback: database
        return await _getLastKnownZipCodeFromDatabase();
      } catch (_) {
        return null;
      }
    }
  }

  /// Get city and state from ZIP code
  /// Returns format: "City, State" or null if not found
  static Future<String?> getCityStateFromZip(String zipCode) async {
    try {
      final zipResult = await _searchByZip(zipCode);
      if (zipResult != null) {
        return zipResult['display']; // Returns "City, State"
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting city/state from ZIP: $e');
      }
      return null;
    }
  }

  /// Set manual location override
  static Future<void> setManualLocation({
    required String displayName,
    String? zipCode,
    double? latitude,
    double? longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userPrefix = _getUserCachePrefix();
    
    // Save to user-specific cache
    await prefs.setString('${userPrefix}${_keyLocationMode}', 'manual');
    await prefs.setString('${userPrefix}${_keyManualLocation}', displayName);
    
    if (zipCode != null) {
      await prefs.setString('${userPrefix}${_keyManualZip}', zipCode);
      await prefs.setString('${userPrefix}cached_zip', zipCode);
      
      // Also save to database for the logged-in user (user-specific)
      try {
        final supa = Supabase.instance.client;
        final user = supa.auth.currentUser;
        if (user != null) {
          await supa
              .from('users')
              .update({'last_known_zip_code': zipCode})
              .eq('id', user.id);
          
          if (kDebugMode) {
            print('[LocationService] Saved manual location ZIP to database for user: $zipCode');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[LocationService] Error saving manual location to database: $e');
        }
        // Continue - SharedPreferences is still saved
      }
    }
    
    // If coordinates provided, store them
    if (latitude != null && longitude != null) {
      await prefs.setDouble('manual_lat', latitude);
      await prefs.setDouble('manual_lng', longitude);
      await prefs.setDouble('cached_lat', latitude);
      await prefs.setDouble('cached_lng', longitude);
    } else if (zipCode != null) {
      // Try to get coordinates from ZIP code
      try {
        final zipResult = await _searchByZip(zipCode);
        if (zipResult != null) {
          // Use geocoding to get coordinates
          final locations = await locationFromAddress('$displayName, USA');
          if (locations.isNotEmpty) {
            await prefs.setDouble('manual_lat', locations.first.latitude);
            await prefs.setDouble('manual_lng', locations.first.longitude);
            await prefs.setDouble('cached_lat', locations.first.latitude);
            await prefs.setDouble('cached_lng', locations.first.longitude);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[LocationService] Could not get coordinates for manual location: $e');
        }
      }
    }
    
    await prefs.setString('${userPrefix}${_keyManualCity}', displayName);
  }

  /// Switch back to auto (device) location
  static Future<void> useAutoLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final userPrefix = _getUserCachePrefix();
    await prefs.setString('${userPrefix}${_keyLocationMode}', 'auto');
  }

  /// Check if using manual location
  static Future<bool> isUsingManualLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final userPrefix = _getUserCachePrefix();
    final mode = prefs.getString('${userPrefix}${_keyLocationMode}') ?? 
                 prefs.getString(_keyLocationMode) ?? 'auto';
    return mode == 'manual';
  }

  /// Clear location cache (SharedPreferences)
  /// Should be called on logout to prevent location bleeding between users
  static Future<void> clearLocationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLocationMode);
      await prefs.remove(_keyManualLocation);
      await prefs.remove(_keyManualCity);
      await prefs.remove(_keyManualZip);
      await prefs.remove('manual_lat');
      await prefs.remove('manual_lng');
      await prefs.remove('cached_location');
      await prefs.remove('cached_lat');
      await prefs.remove('cached_lng');
      await prefs.remove('cached_zip');
      
      if (kDebugMode) {
        print('[LocationService] Cleared location cache from SharedPreferences');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error clearing location cache: $e');
      }
    }
  }

  /// Get current device position
  static Future<Position?> _getCurrentPosition() async {
    try {
      if (kDebugMode) {
        print('[LocationService] Starting position request...');
      }
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (kDebugMode) {
        print('[LocationService] Location service enabled: $serviceEnabled');
      }
      if (!serviceEnabled) {
        if (kDebugMode) {
          print('[LocationService] Location services are disabled');
        }
        return null;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (kDebugMode) {
        print('[LocationService] Current permission: $permission');
      }
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (kDebugMode) {
          print('[LocationService] Permission after request: $permission');
        }
        if (permission == LocationPermission.denied) {
          if (kDebugMode) {
            print('[LocationService] Location permission denied');
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          print('[LocationService] Location permission permanently denied');
        }
        return null;
      }

      if (kDebugMode) {
        print('[LocationService] Getting position...');
      }
      
      // Get current position - remove timeLimit for web compatibility
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(
        const Duration(seconds: 15), // Longer timeout for web
        onTimeout: () {
          if (kDebugMode) {
            print('[LocationService] Position request timed out after 15s');
          }
          throw TimeoutException('Location request timed out');
        },
      );
      
      if (kDebugMode) {
        print('[LocationService] Got position: ${position.latitude}, ${position.longitude}');
      }
      
      return position;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting position: $e');
      }
      return null;
    }
  }

  /// Convert position to city name
  static Future<String?> _getCityFromPosition(Position position) async {
    try {
      // Use geocoding package for reverse geocoding
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality ?? place.subAdministrativeArea;
        final state = place.administrativeArea;

        if (city != null && state != null) {
          // Return abbreviated state (e.g., "Edison, NJ")
          final stateAbbr = _getStateAbbreviation(state);
          return '$city, $stateAbbr';
        } else if (city != null) {
          return city;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting city from position: $e');
      }
      return null;
    }
  }

  /// Convert position to ZIP code
  static Future<String?> getZipFromPosition(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        return placemarks.first.postalCode;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting ZIP from position: $e');
      }
      return null;
    }
  }

  /// Search for locations by name or ZIP code
  static Future<List<Map<String, String>>> searchLocations(String query) async {
    final results = <Map<String, String>>[];

    // If query looks like a ZIP code, search by ZIP
    if (RegExp(r'^\d{5}$').hasMatch(query)) {
      final zipResult = await _searchByZip(query);
      if (zipResult != null) {
        results.add(zipResult);
      }
    } else {
      // Search by city name
      final cityResults = await _searchByCity(query);
      results.addAll(cityResults);
    }

    return results;
  }

  /// Search location by ZIP code
  static Future<Map<String, String>?> _searchByZip(String zipCode) async {
    try {
      final url = Uri.parse('https://api.zippopotam.us/us/$zipCode');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final place = places[0] as Map<String, dynamic>;
          final city = place['place name'] as String?;
          final state = place['state abbreviation'] as String?;
          if (city != null && state != null) {
            return {
              'display': '$city, $state',
              'zip': zipCode,
              'city': city,
              'state': state,
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error searching by ZIP: $e');
      }
    }
    return null;
  }

  /// Search locations by city name
  static Future<List<Map<String, String>>> _searchByCity(String query) async {
    try {
      // Use geocoding to search for locations
      final locations = await locationFromAddress('$query, USA');

      if (locations.isNotEmpty) {
        final results = <Map<String, String>>[];

        for (final location in locations.take(5)) {
          try {
            final placemarks = await placemarkFromCoordinates(
              location.latitude,
              location.longitude,
            );

            if (placemarks.isNotEmpty) {
              final place = placemarks.first;
              final city = place.locality ?? place.subAdministrativeArea;
              final state = place.administrativeArea;
              final zip = place.postalCode;

              if (city != null && state != null && zip != null) {
                final stateAbbr = _getStateAbbreviation(state);
                results.add({
                  'display': '$city, $stateAbbr',
                  'zip': zip,
                  'city': city,
                  'state': stateAbbr,
                });
              }
            }
          } catch (e) {
            // Skip this location if there's an error
            continue;
          }
        }

        return results;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error searching by city: $e');
      }
    }
    return [];
  }

  /// Get state abbreviation from full name
  static String _getStateAbbreviation(String stateName) {
    final stateMap = {
      'Alabama': 'AL', 'Alaska': 'AK', 'Arizona': 'AZ', 'Arkansas': 'AR',
      'California': 'CA', 'Colorado': 'CO', 'Connecticut': 'CT', 'Delaware': 'DE',
      'Florida': 'FL', 'Georgia': 'GA', 'Hawaii': 'HI', 'Idaho': 'ID',
      'Illinois': 'IL', 'Indiana': 'IN', 'Iowa': 'IA', 'Kansas': 'KS',
      'Kentucky': 'KY', 'Louisiana': 'LA', 'Maine': 'ME', 'Maryland': 'MD',
      'Massachusetts': 'MA', 'Michigan': 'MI', 'Minnesota': 'MN', 'Mississippi': 'MS',
      'Missouri': 'MO', 'Montana': 'MT', 'Nebraska': 'NE', 'Nevada': 'NV',
      'New Hampshire': 'NH', 'New Jersey': 'NJ', 'New Mexico': 'NM', 'New York': 'NY',
      'North Carolina': 'NC', 'North Dakota': 'ND', 'Ohio': 'OH', 'Oklahoma': 'OK',
      'Oregon': 'OR', 'Pennsylvania': 'PA', 'Rhode Island': 'RI', 'South Carolina': 'SC',
      'South Dakota': 'SD', 'Tennessee': 'TN', 'Texas': 'TX', 'Utah': 'UT',
      'Vermont': 'VT', 'Virginia': 'VA', 'Washington': 'WA', 'West Virginia': 'WV',
      'Wisconsin': 'WI', 'Wyoming': 'WY',
    };

    return stateMap[stateName] ?? stateName;
  }
}

