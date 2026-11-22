#!/bin/sh
# Builds the macOS app (ad-hoc signed) and copies it to build/Swiftfin.app.
# Usage: Tools/macOS/build.sh [Debug|Release]
set -eu
cd "$(dirname "$0")/../.."
CONFIGURATION="${1:-Debug}"
mkdir -p build
# Override to keep parallel builds from fighting over one build database
DERIVED_DATA="${SWIFTFIN_DERIVED_DATA:-build/DerivedData}"
LOG="$DERIVED_DATA/macos-build.log"
ERRORS="$DERIVED_DATA/macos-errors.txt"
mkdir -p "$DERIVED_DATA"
set +e
xcodebuild \
    -project Swiftfin.xcodeproj \
    -scheme "Swiftfin macOS" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -IDEBuildingContinueBuildingAfterErrors=YES \
    build > "$LOG" 2>&1
STATUS=$?
set -e
grep -E "^/.*error:" "$LOG" | sed "s|$PWD/||" | sort -u > "$ERRORS" || true
echo "xcodebuild exit $STATUS, $(wc -l < "$ERRORS" | tr -d ' ') unique errors ($ERRORS)"
if [ "$STATUS" -eq 0 ]; then
    rm -rf build/Swiftfin.app
    cp -R "$DERIVED_DATA/Build/Products/$CONFIGURATION/Swiftfin.app" build/Swiftfin.app
    echo "build/Swiftfin.app"
fi
exit $STATUS
