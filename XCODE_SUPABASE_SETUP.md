# Xcode Supabase Configuration Guide

## ✅ Quick Fix (Recommended)

The Supabase credentials have been added to the xcconfig files. However, for Xcode builds, you may need to set them in the build arguments.

### Option 1: Use Xcode Scheme Arguments (Easiest)

1. Open Xcode
2. Open your project: `ios/Runner.xcworkspace` (NOT .xcodeproj)
3. Go to **Product → Scheme → Edit Scheme...**
4. Select **Run** in the left sidebar
5. Go to the **Arguments** tab
6. Under **Arguments Passed On Launch**, add:
   ```
   --dart-define=SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co
   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw
   ```

### Option 2: Use Build Settings (Alternative)

1. Open Xcode
2. Select the **Runner** project
3. Select the **Runner** target
4. Go to **Build Settings**
5. Search for "Other Swift Flags"
6. Add:
   ```
   -DSUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co -DSUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw
   ```

### Option 3: Use Flutter Command Line (Recommended for Development)

Instead of building from Xcode, use the terminal:

```bash
flutter run --dart-define=SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw
```

Or use the provided script:
```bash
./run_app.sh
```

## Current Configuration

- ✅ Credentials added to `ios/Flutter/Debug.xcconfig`
- ✅ Credentials added to `ios/Flutter/Release.xcconfig`
- ✅ Environment variables set in Xcode scheme (for runtime)
- ⚠️ Build arguments may still need to be set in Xcode scheme

## After Configuration

1. **Clean Build Folder**: Product → Clean Build Folder (Shift + Cmd + K)
2. **Rebuild**: Product → Build (Cmd + B)
3. **Run**: Product → Run (Cmd + R)

## Troubleshooting

If you still see "Configuration Required":
- Verify the credentials are correct
- Check that the scheme arguments are set correctly
- Try cleaning and rebuilding
- Use the Flutter command line instead of Xcode for development

