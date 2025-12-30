#!/bin/bash
# This script ensures Supabase credentials are available during Flutter builds

# Read FLUTTER_DART_DEFINES from xcconfig file if it exists
XCCONFIG_FILE=""
if [ "${CONFIGURATION}" == "Debug" ]; then
    XCCONFIG_FILE="${SRCROOT}/Flutter/Debug.xcconfig"
elif [ "${CONFIGURATION}" == "Release" ] || [ "${CONFIGURATION}" == "Profile" ]; then
    XCCONFIG_FILE="${SRCROOT}/Flutter/Release.xcconfig"
fi

if [ -f "$XCCONFIG_FILE" ]; then
    # Extract FLUTTER_DART_DEFINES from xcconfig
    DART_DEFINES=$(grep "^FLUTTER_DART_DEFINES=" "$XCCONFIG_FILE" | cut -d'=' -f2-)
    if [ -n "$DART_DEFINES" ]; then
        export FLUTTER_DART_DEFINES="$DART_DEFINES"
    fi
fi

# Call the original Flutter build script
exec "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" "$@"

