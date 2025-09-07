#!/bin/bash

set -e

PROJECT_NAME="swingmaster"
SCHEME="swingmaster"
WORKSPACE="${PROJECT_NAME}.xcodeproj/project.xcworkspace"

echo "🏗️  Building iOS project: $PROJECT_NAME"
echo "Working directory: $(pwd)"

if [ ! -d "$WORKSPACE" ]; then
    echo "❌ Workspace not found: $WORKSPACE"
    exit 1
fi

echo "📱 Building for iOS Simulator..."
xcodebuild -workspace "$WORKSPACE" \
           -scheme "$SCHEME" \
           -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
           -configuration Debug \
           build

echo "✅ Build completed successfully!"