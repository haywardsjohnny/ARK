# Fix Xcode Configuration Error on iPhone

The issue is that Xcode may not be reading `FLUTTER_DART_DEFINES` from the xcconfig files when building directly from Xcode. Here are the solutions:

## Solution 1: Build from Terminal (Recommended)

Build directly from the terminal, which will properly use the xcconfig files:

```bash
cd /Users/saireddykasthuri/sportsdug_app

# For Debug build
flutter run -d Setrico --dart-define=SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw

# Or use the run script
./run_app.sh
```

## Solution 2: Set Build Settings in Xcode

If you need to build from Xcode directly:

1. **Open Xcode**: Open `ios/Runner.xcworkspace` (NOT .xcodeproj)
2. **Select Runner project** in the navigator
3. **Select Runner target**
4. **Go to Build Settings tab**
5. **Click the "+" button** to add a User-Defined Setting
6. **Add `FLUTTER_DART_DEFINES`** with value:
   ```
   SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co,SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw
   ```
7. **Make sure it's set for both Debug and Release configurations**

## Solution 3: Use Scheme Environment Variables

The scheme already has environment variables set, but those are for runtime, not build time. The build-time configuration needs to be in build settings or xcconfig files.

## Why This Happens

When building from Xcode directly, the Flutter build scripts need to read `FLUTTER_DART_DEFINES` from the build settings. While xcconfig files should work, sometimes Xcode doesn't properly propagate these values to the Flutter build scripts during the build process.

The most reliable solution is to either:
- Build from the terminal using `flutter run` with `--dart-define` flags
- Set `FLUTTER_DART_DEFINES` as a User-Defined build setting directly in Xcode

## Quick Test

To verify if the config is being read, add this to your app temporarily:

```dart
print('SUPABASE_URL: ${AppConfig.supabaseUrl}');
print('SUPABASE_ANON_KEY: ${AppConfig.supabaseAnonKey.substring(0, 20)}...');
```

If these print empty strings, the dart-define values aren't being passed correctly.

