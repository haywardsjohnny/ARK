# Location Feature - Implementation Guide

## Overview
The app now uses **device location** by default with the ability to manually search and override the location. This provides a more accurate user experience while giving users full control.

## Features Implemented

### 1. **Auto-Detect Device Location** 
- Uses GPS to get current latitude/longitude
- Converts to city name (e.g., "Edison, NJ")
- Extracts ZIP code for game discovery
- Falls back to profile ZIP if GPS is unavailable

### 2. **Manual Location Search**
- Search by city name (e.g., "New York")
- Search by ZIP code (e.g., "08902")
- Real-time search results
- Saves selected location for future sessions

### 3. **User Interface**
- **Home Screen**: Location displayed with blue text and edit icon
- **Tap to Change**: Opens location picker dialog
- **Visual Feedback**: Shows "Loading..." while fetching location
- **Persistence**: Remembers manual selections between sessions

## How It Works

### Location Service (`lib/services/location_service.dart`)
```dart
// Get display location (city, state)
LocationService.getCurrentLocationDisplay() → "Edison, NJ"

// Get ZIP code for game discovery  
LocationService.getCurrentZipCode() → "08902"

// Set manual location
LocationService.setManualLocation(
  displayName: "New York, NY",
  zipCode: "10001"
)

// Switch back to auto
LocationService.useAutoLocation()
```

### Priority Order
1. **Manual Location** (if user selected)
   - Uses stored city name and ZIP
   - Persists between sessions
   
2. **Device GPS Location** (default)
   - Gets current position
   - Converts to city/ZIP
   - Updates automatically
   
3. **Profile ZIP** (fallback)
   - Uses `users.base_zip_code`
   - Legacy compatibility

## User Experience

### First Time User
1. App requests location permission (on mobile)
2. Automatically detects city from GPS
3. Shows "Hi [Name] | 📍 Edison, NJ"
4. Uses ZIP code to find nearby games

### Changing Location
1. Tap the blue location text on home screen
2. Dialog opens with two options:
   - ✅ **Use Device Location** (auto-detect)
   - 🔍 **Search Location** (manual search)
3. If searching manually:
   - Type city name or ZIP code
   - Select from results
   - Location is saved
4. Tap "Use Device Location" to switch back to auto

### Web vs Mobile
- **Web**: Location detected via browser geolocation API (requires user permission)
- **Mobile**: Uses native GPS (permissions added to AndroidManifest.xml and Info.plist)

## Files Modified

### New Files
- `lib/services/location_service.dart` - Core location logic
- `lib/widgets/location_picker_dialog.dart` - Location picker UI

### Updated Files
- `lib/screens/home_tabs/home_tabs_screen.dart` - Integrated location service
- `lib/screens/home_tabs/home_tabs_controller.dart` - Uses LocationService for ZIP
- `pubspec.yaml` - Added location packages
- `android/app/src/main/AndroidManifest.xml` - Android permissions
- `ios/Runner/Info.plist` - iOS permissions

## Permissions

### Android (`AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### iOS (`Info.plist`)
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show nearby sports games and events</string>
```

### Web
- Browser prompts user for location permission
- No additional configuration needed

## Testing

### Test Scenarios

1. **Auto Location (Web)**
   - Open app in Chrome
   - Allow location when prompted
   - Should show current city

2. **Manual Search**
   - Tap location text
   - Select "Search Location"
   - Type "New York" or "10001"
   - Select result
   - Should show "New York, NY"

3. **Switch Back to Auto**
   - Tap location text
   - Select "Use Device Location"
   - Click "Use Device Location" button
   - Should show current city

4. **Persistence**
   - Set manual location
   - Refresh page
   - Should remember manual location

## Technical Details

### Packages Used
- `geolocator: ^12.0.0` - GPS location
- `geocoding: ^3.0.0` - Lat/lng to address
- `shared_preferences: ^2.2.0` - Persistence
- `http: ^1.1.0` - ZIP code API

### APIs
- **Zippopotam.us**: ZIP code to city conversion
  - `https://api.zippopotam.us/us/{zipCode}`
  - Free, no API key required

### State Management
- Uses `SharedPreferences` for storing:
  - `location_mode`: 'auto' or 'manual'
  - `manual_location`: Display name
  - `manual_zip`: ZIP code

## Known Limitations

1. **Permission Required**: Users must grant location permission for auto-detection
2. **GPS Accuracy**: Indoor locations may be less accurate
3. **Web HTTPS**: Location API requires HTTPS in production
4. **Rate Limits**: Zippopotam.us has rate limits (not documented)

## Future Enhancements

- [ ] Reload nearby games when location changes
- [ ] Show distance to each game from current location
- [ ] Remember recent locations
- [ ] Add "Detect my location" button in game creation
- [ ] Show location permission prompt if denied

## Troubleshooting

### "Location" shows instead of city name
- Check browser location permission
- Verify GPS is enabled (mobile)
- Check console for errors

### Manual search returns no results
- Ensure query is at least 3 characters
- Try ZIP code instead of city name
- Check internet connection

### Location doesn't persist
- Clear browser cache and try again
- Check SharedPreferences is working
- Verify no errors in console

