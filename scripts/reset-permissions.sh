#!/bin/bash
# Reset screen recording permission for Scoosho and relaunch
# Usage: ./scripts/reset-permissions.sh

BUNDLE_ID="com.mickeey2525.scoosho"
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Scoosho-*/Build/Products/Debug/Scoosho.app -maxdepth 0 2>/dev/null | head -1)

echo "Resetting screen recording permission for $BUNDLE_ID..."
tccutil reset ScreenCapture "$BUNDLE_ID"

echo "Killing existing Scoosho instances..."
pkill -x Scoosho 2>/dev/null
sleep 1

if [ -n "$APP_PATH" ]; then
    echo "Launching $APP_PATH"
    open "$APP_PATH"
else
    echo "Scoosho.app not found in DerivedData. Build first with xcodebuild."
fi
