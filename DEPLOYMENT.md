# SPORTSDUG App - Deployment Guide

## 🚀 Production Deployment Checklist

### Pre-Deployment

- [ ] All tests passing
- [ ] Code review completed
- [ ] Security audit completed
- [ ] Performance testing completed
- [ ] App icons and splash screens configured
- [ ] Privacy policy URL configured
- [ ] Terms of service URL configured
- [ ] App store listings prepared
- [ ] Screenshots and marketing materials ready

### Environment Setup

1. **Create environment files:**
   ```bash
   cp .env.example .env.production
   # Edit .env.production with production values
   ```

2. **Required Environment Variables:**
   - `SUPABASE_URL` - Your Supabase project URL
   - `SUPABASE_ANON_KEY` - Your Supabase anon key
   - `SENTRY_DSN` - (Optional) Sentry DSN for error tracking
   - `ENABLE_FIREBASE` - Set to "true" if using Firebase
   - `ENV` - Set to "production" for production builds

### Android Deployment

#### 1. Generate Signing Key

```bash
keytool -genkey -v -keystore android/app/keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias sportsdug
```

**⚠️ IMPORTANT:** Store the keystore file and passwords securely. You cannot update the app without it.

#### 2. Configure Signing

Add to `android/local.properties` (DO NOT commit this file):
```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=sportsdug
storeFile=path/to/keystore.jks
```

#### 3. Build Release

```bash
# Using build script
export SUPABASE_URL=your_url
export SUPABASE_ANON_KEY=your_key
export ENV=production
./scripts/build_android.sh

# Or manually
flutter build appbundle --release \
  --dart-define=ENV=production \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

#### 4. Upload to Google Play Console

1. Go to [Google Play Console](https://play.google.com/console)
2. Create new app or select existing
3. Go to Production > Create new release
4. Upload `build/app/outputs/bundle/release/app-release.aab`
5. Fill in release notes
6. Review and roll out

### iOS Deployment

#### 1. Configure Xcode

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select Runner target
3. Go to Signing & Capabilities
4. Select your Team
5. Ensure Bundle Identifier is unique (e.g., `com.sportsdug.app`)

#### 2. Build Archive

```bash
# Using build script
export SUPABASE_URL=your_url
export SUPABASE_ANON_KEY=your_key
export ENV=production
./scripts/build_ios.sh

# Then in Xcode:
# 1. Select "Any iOS Device" as target
# 2. Product > Archive
# 3. Distribute App
```

#### 3. Upload to App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Create new app or select existing
3. Upload via Xcode Organizer or Transporter
4. Configure app information
5. Submit for review

### Firebase Setup (Optional)

1. Create Firebase project at [Firebase Console](https://console.firebase.google.com)
2. Add Android app:
   - Download `google-services.json` to `android/app/`
3. Add iOS app:
   - Download `GoogleService-Info.plist` to `ios/Runner/`
4. Enable Analytics and Crashlytics
5. Set `ENABLE_FIREBASE=true` in build

### Sentry Setup (Optional)

1. Create account at [Sentry](https://sentry.io)
2. Create new project (Flutter)
3. Copy DSN
4. Set `SENTRY_DSN` in build environment

### Version Management

Update version in `pubspec.yaml`:
```yaml
version: 1.0.0+1  # version+buildNumber
```

- Version: User-facing version (e.g., 1.0.0)
- Build Number: Increment for each build (e.g., +1, +2)

### CI/CD Setup

See `.github/workflows/` for GitHub Actions workflows.

### Monitoring Post-Deployment

1. **Sentry:** Monitor errors and crashes
2. **Firebase Analytics:** Track user behavior
3. **App Store Connect:** Monitor app performance
4. **Google Play Console:** Monitor app health

### Rollback Procedure

**Android:**
- Google Play: Create new release with previous version
- Can take 1-2 hours to propagate

**iOS:**
- App Store: Submit new version with fix
- Cannot rollback immediately (requires new submission)

### Troubleshooting

**Build fails:**
- Check environment variables are set
- Verify signing configuration
- Clean build: `flutter clean && flutter pub get`

**App crashes on launch:**
- Check Sentry for error logs
- Verify Supabase configuration
- Test on physical device

**Store rejection:**
- Review rejection reason
- Fix issues
- Resubmit with explanation

## 📚 Additional Resources

- [Flutter Deployment Guide](https://flutter.dev/docs/deployment)
- [Google Play Console Help](https://support.google.com/googleplay/android-developer)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)

