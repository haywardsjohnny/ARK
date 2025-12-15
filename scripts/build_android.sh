#!/bin/bash
# Android Production Build Script

set -e

echo "🚀 Building Android Release..."

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
echo "📱 Building Android App Bundle..."

# Build app bundle
flutter build appbundle \
  --release \
  --dart-define=ENV=$ENV \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define=SENTRY_DSN=$SENTRY_DSN \
  --dart-define=ENABLE_FIREBASE=$ENABLE_FIREBASE

echo "✅ Build complete! App bundle location:"
echo "   build/app/outputs/bundle/release/app-release.aab"

