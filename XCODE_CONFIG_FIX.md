# Xcode Configuration Fix for Supabase

The xcconfig files are correctly configured with Supabase credentials. If Xcode still shows a config error, try these steps:

## Option 1: Clean and Rebuild in Xcode

1. **Close Xcode completely**
2. **Open Xcode again**
3. **Clean Build Folder**: `Product` → `Clean Build Folder` (or press `Cmd+Shift+K`)
4. **Close Xcode again**
5. **Delete Derived Data**:
   - Open Terminal
   - Run: `rm -rf ~/Library/Developer/Xcode/DerivedData`
6. **Reopen Xcode**
7. **Build again**: `Product` → `Build` (or press `Cmd+B`)

## Option 2: Verify Build Settings in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode (NOT the .xcodeproj file)
2. Select the **Runner** project in the navigator
3. Select the **Runner** target
4. Go to the **Build Settings** tab
5. Search for `FLUTTER_DART_DEFINES`
6. Verify it shows: `SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co,SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw`

If it's not showing, the xcconfig files might not be properly linked. Check:
- **Info** tab → **Configurations**
- Debug should use `Flutter/Debug.xcconfig`
- Release should use `Flutter/Release.xcconfig`

## Option 3: Build from Terminal (Alternative)

If Xcode continues to have issues, you can build from the terminal which will use the xcconfig files:

```bash
cd /Users/saireddykasthuri/sportsdug_app
flutter build ios --debug
```

Or for release:
```bash
flutter build ios --release
```

## Current Configuration Files

The following files are correctly configured:
- `ios/Flutter/Debug.xcconfig` - Contains FLUTTER_DART_DEFINES with Supabase credentials
- `ios/Flutter/Release.xcconfig` - Contains FLUTTER_DART_DEFINES with Supabase credentials
- `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` - Contains environment variables for runtime

## If Still Not Working

If the error persists, the issue might be that the Flutter build system isn't reading the FLUTTER_DART_DEFINES from xcconfig properly. In that case, you may need to:

1. Set the values in Xcode's build settings directly
2. Or use the terminal build commands with `--dart-define` flags

