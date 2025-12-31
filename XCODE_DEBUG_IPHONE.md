# Debugging on Real iPhone from Xcode

When building and debugging directly from Xcode (not using Flutter CLI), you need to ensure Supabase credentials are passed correctly.

## ✅ Solution: Configure Xcode Scheme

### Step 1: Open Xcode Workspace
1. Open `ios/Runner.xcworkspace` (NOT `.xcodeproj`)
2. Make sure your iPhone is connected and selected as the build target

### Step 2: Edit Scheme Arguments
1. Go to **Product → Scheme → Edit Scheme...** (or press `Cmd + <`)
2. Select **Run** in the left sidebar
3. Go to the **Arguments** tab
4. Under **Arguments Passed On Launch**, add these two lines:
   ```
   --dart-define=SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co
   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw
   ```

### Step 3: Clean and Rebuild
1. **Product → Clean Build Folder** (Shift + Cmd + K)
2. **Product → Build** (Cmd + B)
3. **Product → Run** (Cmd + R) to deploy to your iPhone

## Alternative: Use Flutter CLI (Easier for Development)

Instead of building from Xcode, you can use Flutter CLI which automatically handles the credentials:

```bash
# From the project root
flutter run --dart-define=SUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw
```

Or use the provided script:
```bash
./run_app_ios.sh
```

## Verify Configuration

After setting up, the app should:
- ✅ Not show the "Configuration Required" screen
- ✅ Connect to Supabase successfully
- ✅ Allow you to sign in/sign up

## Troubleshooting

### Still seeing "Configuration Required"?
1. **Verify scheme is saved**: Make sure you clicked "Close" after editing the scheme
2. **Check build configuration**: Ensure you're using the correct scheme (Debug/Release)
3. **Clean build**: Delete derived data:
   - Xcode → Preferences → Locations → Derived Data → Delete
   - Or: `rm -rf ~/Library/Developer/Xcode/DerivedData`
4. **Verify credentials**: Double-check the URL and key are correct
5. **Check Xcode console**: Look for any error messages about missing defines

### Build Errors?
- Make sure you opened `.xcworkspace`, not `.xcodeproj`
- Run `pod install` in the `ios/` directory if needed
- Ensure your iPhone is trusted and developer mode is enabled

### Network Issues?
- Ensure your iPhone and Mac are on the same network
- Check that your Supabase project is accessible
- Verify firewall settings aren't blocking connections

## Notes

- The credentials in `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig` are set, but Xcode builds may not always read them correctly
- Setting them in the scheme ensures they're always passed during builds
- For production builds, consider using different credentials via environment-specific schemes

