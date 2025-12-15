# How to Run SPORTSDUG App

## Quick Start

### Option 1: Run with Supabase Credentials (Recommended)

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=your_supabase_project_url \
  --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key
```

**Example:**
```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://abcdefgh.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Option 2: Run Without Credentials (Demo Mode)

The app will now show a configuration screen instead of crashing:

```bash
flutter run -d chrome
```

You'll see a helpful message explaining what credentials are needed.

## Where to Find Supabase Credentials

1. Go to your [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Go to **Settings** → **API**
4. Copy:
   - **Project URL** → Use as `SUPABASE_URL`
   - **anon/public key** → Use as `SUPABASE_ANON_KEY`

## Running on Different Platforms

### Web (Chrome)
```bash
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### iOS Simulator
```bash
flutter run -d ios --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### Android Emulator
```bash
flutter run -d android --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Optional: Firebase & Sentry

If you want to enable Firebase Analytics and Sentry:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=ENABLE_FIREBASE=true \
  --dart-define=SENTRY_DSN=your_sentry_dsn
```

## Troubleshooting

**Blank white screen?**
- Check browser console (F12) for errors
- Make sure Supabase credentials are correct
- Verify network connection

**App crashes on startup?**
- Check that Supabase URL and key are valid
- Ensure no typos in `--dart-define` flags
- Look at terminal output for error messages

