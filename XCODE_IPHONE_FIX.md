# Fix Supabase Configuration Error on iPhone (Xcode Build)

## The Problem

When building directly from Xcode, the `FLUTTER_DART_DEFINES` values in the xcconfig files may not be properly passed to the Flutter build scripts, causing the "Configuration required" error.

## ✅ Solution 1: Build from Terminal (Easiest & Most Reliable)

Instead of building from Xcode, build from the terminal:

```bash
cd /Users/saireddykasthuri/sportsdug_app
./run_app_ios.sh
```

Or manually:
```bash
flutter run -d Setrico \
  --dart-define=SUPABASE_URL="https://bcrglducvsimtghrgrpv.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw"
```

This will:
- Build the app with the correct Supabase credentials
- Install it on your iPhone (Setrico)
- Launch it automatically

## ✅ Solution 2: Set Build Settings in Xcode (If you must build from Xcode)

If you need to build from Xcode directly:

1. **Open Xcode**: Open `ios/Runner.xcworkspace` (make sure it's `.xcworkspace`, NOT `.xcodeproj`)

2. **Select the Runner project** in the left navigator

3. **Select the Runner target** (under TARGETS)

4. **Go to the "Build Settings" tab**

5. **Click the "+" button** at the top (next to "All" and "Basic") and select **"Add User-Defined Setting"**

6. **Name it**: `FLUTTER_DART_DEFINES`

7. **Set the value** for both Debug and Release:
   ```
   SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co,SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw
   ```

8. **Clean and rebuild**: `Product` → `Clean Build Folder` (Cmd+Shift+K), then build (Cmd+B)

## Why Solution 1 is Better

- ✅ More reliable - terminal builds always work with dart-define flags
- ✅ Faster - no need to modify Xcode project settings
- ✅ Easier - just run one command
- ✅ Portable - works on any machine with the script

## Verification

After building, the app should launch without the "Configuration required" error. You can verify by checking that the app connects to Supabase successfully (e.g., login screen appears, data loads, etc.).

## Current Configuration Files

The following files are correctly configured (but may not be read by Xcode):
- ✅ `ios/Flutter/Debug.xcconfig` - Contains FLUTTER_DART_DEFINES
- ✅ `ios/Flutter/Release.xcconfig` - Contains FLUTTER_DART_DEFINES

These work perfectly when building from the terminal with `flutter run`.

