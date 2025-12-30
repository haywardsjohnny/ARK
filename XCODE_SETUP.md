# Xcode Setup for Supabase Credentials

## Quick Setup (Already Configured)

The Supabase credentials have been added to the xcconfig files. You should be able to build and run from Xcode now.

## Alternative: Manual Xcode Scheme Configuration

If you prefer to set credentials manually in Xcode:

### Method 1: Edit Scheme (Recommended)

1. Open Xcode
2. Select **Product → Scheme → Edit Scheme...**
3. Select **Run** in the left sidebar
4. Go to the **Arguments** tab
5. Under **Environment Variables**, add:
   - `SUPABASE_URL` = `https://bcrglducvsimtghrgrpv.supabase.co`
   - `SUPABASE_ANON_KEY` = `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw`

### Method 2: Build Settings

1. Open Xcode
2. Select the **Runner** project
3. Select the **Runner** target
4. Go to **Build Settings**
5. Search for "Other Swift Flags" or "Other C Flags"
6. Add: `-DSUPABASE_URL=https://bcrglducvsimtghrgrpv.supabase.co -DSUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjcmdsZHVjdnNpbXRnaHJncnB2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMzE3NTUsImV4cCI6MjA4MDkwNzc1NX0.ipkLvdxxNzXxH8_oJrWtykzaob7KfDdluq273-IZWuw`

## Verify Configuration

After setup, clean and rebuild:
1. **Product → Clean Build Folder** (Shift + Cmd + K)
2. **Product → Build** (Cmd + B)
3. Run the app

## Notes

- The credentials are now in `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`
- These files are gitignored by default, so credentials won't be committed
- For production, use environment-specific credentials

