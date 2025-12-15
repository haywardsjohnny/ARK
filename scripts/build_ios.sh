#!/bin/bash
# iOS Production Build Script

set -e

echo "🚀 Building iOS Release..."

# Check for required environment variables
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo "❌ Error: SUPABASE_URL and SUPABASE_ANON_KEY must be set"
    exit 1
fi

# Set environment (default to production)
ENV=${ENV:-production}
SENTRY_DSN=${SENTRY_DSN:-""}
ENABLE_FIREBASE=${ENABLE_FIREBASE:-"false"}

echo "📦 Environment: $ENV"
echo "📱 Building iOS Archive..."

# Clean build
flutter clean

# Build iOS
flutter build ios \
  --release \
  --no-codesign \
  --dart-define=ENV=$ENV \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define=SENTRY_DSN=$SENTRY_DSN \
  --dart-define=ENABLE_FIREBASE=$ENABLE_FIREBASE

echo "✅ Build complete! Next steps:"
echo "   1. Open ios/Runner.xcworkspace in Xcode"
echo "   2. Select 'Any iOS Device' as target"
echo "   3. Product > Archive"
echo "   4. Distribute via App Store Connect"

