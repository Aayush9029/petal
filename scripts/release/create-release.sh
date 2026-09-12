#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
SCHEME="petal"
PRODUCT_NAME="petal"
SIGNING_IDENTITY="Developer ID Application: Optimal Life Technologies, Inc (6Q29HJZ4AG)"
TEAM_ID="6Q29HJZ4AG"
API_KEY_ID="KDZQQND374"
API_ISSUER_ID="32b44455-4bec-4cb8-8fbf-eb06754dda95"
SPARKLE_VERSION="2.8.1"

# Use absolute path to avoid xcbeautify shell wrappers
XCODEBUILD=/usr/bin/xcodebuild

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS_DIR="$PROJECT_DIR/scripts/release"
BUILD_DIR="$PROJECT_DIR/build-release"
SECRET_KEYS_DIR="$PROJECT_DIR/secret_keys"
P8_BASE64_FILE="$SECRET_KEYS_DIR/api_key_p8_base64.txt"
P12_BASE64_FILE="$SECRET_KEYS_DIR/certificate_p12_base64.txt"
SPARKLE_PRIVATE_KEY_FILE="$SECRET_KEYS_DIR/sparkle_private_key.txt"

VERSION=""
BUILD_NUMBER=""
SKIP_NOTARIZE=false
BUILD_KEYCHAIN=""

# ─── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
    rm -f "$BUILD_DIR/AuthKey_${API_KEY_ID}.p8" 2>/dev/null || true
    rm -f "$BUILD_DIR/ExportOptions.plist" 2>/dev/null || true
    rm -f "$BUILD_DIR/app-for-notarization.zip" 2>/dev/null || true
    rm -f "$BUILD_DIR/developer_id.p12" 2>/dev/null || true
    # Delete temporary keychain if created
    if [[ -n "$BUILD_KEYCHAIN" && -f "$BUILD_KEYCHAIN" ]]; then
        security delete-keychain "$BUILD_KEYCHAIN" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build, notarize, and package petal into a signed DMG.

Options:
  --version X.Y.Z      Override version (default: read from project.pbxproj)
  --build-number N     Override build number (default: 1)
  --skip-notarize      Skip notarization and stapling steps (debug only)
  --help               Show this help message

Prerequisites:
  - create-dmg (brew install create-dmg)
  - Developer ID certificate at secret_keys/certificate_p12_base64.txt
  - API key at secret_keys/api_key_p8_base64.txt
  - Sparkle private key at secret_keys/sparkle_private_key.txt
  - DMG background at dmg-assets/dmg-bg@2x.jpg
EOF
    exit 0
}

# ─── Parse arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo "Run '$(basename "$0") --help' for usage."
            exit 1
            ;;
    esac
done

# ─── Preflight checks ───────────────────────────────────────────────────────
echo "=== Preflight checks ==="

if ! command -v create-dmg &>/dev/null; then
    echo "Error: create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

if [[ ! -f "$P8_BASE64_FILE" ]]; then
    echo "Error: API key not found at $P8_BASE64_FILE"
    exit 1
fi

if [[ ! -f "$P12_BASE64_FILE" ]]; then
    echo "Error: Developer ID certificate not found at $P12_BASE64_FILE"
    exit 1
fi

if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
    echo "Error: Sparkle private key not found at $SPARKLE_PRIVATE_KEY_FILE"
    exit 1
fi

DMG_BG="$PROJECT_DIR/dmg-assets/dmg-bg@2x.jpg"
if [[ ! -f "$DMG_BG" ]]; then
    echo "Error: DMG background not found at $DMG_BG"
    exit 1
fi

# ─── Resolve Sparkle tools ──────────────────────────────────────────────────
SPARKLE_TOOLS_DIR="$PROJECT_DIR/.derived/sparkle-download/Sparkle-${SPARKLE_VERSION}"
SIGN_UPDATE="$SPARKLE_TOOLS_DIR/bin/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "Downloading Sparkle ${SPARKLE_VERSION} tools..."
    mkdir -p "$PROJECT_DIR/.derived/sparkle-download"
    curl -fsSL \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
        -o "$PROJECT_DIR/.derived/sparkle-download/Sparkle-${SPARKLE_VERSION}.tar.xz"
    rm -rf "$SPARKLE_TOOLS_DIR"
    mkdir -p "$SPARKLE_TOOLS_DIR"
    tar -xf "$PROJECT_DIR/.derived/sparkle-download/Sparkle-${SPARKLE_VERSION}.tar.xz" -C "$SPARKLE_TOOLS_DIR"
fi

# ─── Setup temporary keychain ───────────────────────────────────────────────
# macOS 26 blocks CLI access to Developer ID keys in the login keychain.
# Create a temporary keychain with the cert imported (same approach as CI).
echo "Setting up build keychain..."
BUILD_KEYCHAIN="$BUILD_DIR/build.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

# Prepare build directory (must exist before creating keychain inside it)
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Decode the base64-encoded .p12
P12_DECODED="$BUILD_DIR/developer_id.p12"
base64 --decode < "$P12_BASE64_FILE" > "$P12_DECODED"

# Create temporary keychain
security create-keychain -p "$KEYCHAIN_PASSWORD" "$BUILD_KEYCHAIN"
security set-keychain-settings -lut 21600 "$BUILD_KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$BUILD_KEYCHAIN"

# Import Developer ID certificate with -A (allow all apps), empty password
security import "$P12_DECODED" \
    -P "" \
    -A \
    -t cert \
    -f pkcs12 \
    -k "$BUILD_KEYCHAIN"
rm -f "$P12_DECODED"

# Allow codesign to access the keychain
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$BUILD_KEYCHAIN" >/dev/null 2>&1

# Add build keychain to search list (prepend so it's found first)
EXISTING_KEYCHAINS=$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')
security list-keychains -d user -s "$BUILD_KEYCHAIN" $EXISTING_KEYCHAINS

echo "Build keychain ready."

# Read version from project.pbxproj if not overridden
if [[ -z "$VERSION" ]]; then
    VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT_DIR/petal.xcodeproj/project.pbxproj" \
        | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')
    if [[ -z "$VERSION" ]]; then
        echo "Error: Could not read MARKETING_VERSION from project.pbxproj"
        exit 1
    fi
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="1"
fi

DMG_NAME="Petal-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
ARCHIVE_PATH="$BUILD_DIR/petal.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$PRODUCT_NAME.app"

echo "Version:      $VERSION"
echo "Build number: $BUILD_NUMBER"
echo "DMG:          $DMG_NAME"
echo "Notarize:     $( $SKIP_NOTARIZE && echo 'SKIPPED' || echo 'YES' )"
echo ""

# Decode API key to temp location
base64 --decode < "$P8_BASE64_FILE" > "$BUILD_DIR/AuthKey_${API_KEY_ID}.p8"

# ─── Step 1/10: Archive ─────────────────────────────────────────────────────
echo "=== Step 1/10: Archive ==="
$XCODEBUILD archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    ARCHS=arm64 \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--keychain $BUILD_KEYCHAIN" \
    -quiet
echo "Archive complete."

# ─── Step 2/10: Export ───────────────────────────────────────────────────────
echo "=== Step 2/10: Export archive ==="
cat > "$BUILD_DIR/ExportOptions.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

$XCODEBUILD -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH" \
    -quiet
echo "Export complete."

# ─── Step 3/10: Sign aria2c ─────────────────────────────────────────────────
echo "=== Step 3/10: Sign embedded aria2c ==="
"$SCRIPTS_DIR/sign-aria2c.sh" \
    --app "$APP_PATH" \
    --identity "$SIGNING_IDENTITY" \
    --keychain "$BUILD_KEYCHAIN" \
    --skip-gatekeeper

# ─── Step 4/10: Re-sign app bundle ──────────────────────────────────────────
echo "=== Step 4/10: Re-sign app bundle ==="
codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --keychain "$BUILD_KEYCHAIN" \
    --entitlements "$PROJECT_DIR/petal/petal.entitlements" \
    --options runtime \
    --timestamp \
    "$APP_PATH"
echo "App bundle re-signed."

# ─── Step 5/10: Notarize app ────────────────────────────────────────────────
if $SKIP_NOTARIZE; then
    echo "=== Step 5/10: Notarize app (SKIPPED) ==="
else
    echo "=== Step 5/10: Notarize app ==="
    ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/app-for-notarization.zip"
    xcrun notarytool submit "$BUILD_DIR/app-for-notarization.zip" \
        --key "$BUILD_DIR/AuthKey_${API_KEY_ID}.p8" \
        --key-id "$API_KEY_ID" \
        --issuer "$API_ISSUER_ID" \
        --wait
    echo "App notarization complete."
fi

# ─── Step 6/10: Staple app ──────────────────────────────────────────────────
if $SKIP_NOTARIZE; then
    echo "=== Step 6/10: Staple app (SKIPPED) ==="
else
    echo "=== Step 6/10: Staple app ==="
    xcrun stapler staple "$APP_PATH"
    echo "App stapled."
fi

# ─── Step 7/10: Create DMG ──────────────────────────────────────────────────
echo "=== Step 7/10: Create DMG ==="
"$SCRIPTS_DIR/create-dmg.sh" \
    --app "$APP_PATH" \
    --output "$DMG_PATH"

# ─── Step 8/10: Sign + notarize + staple DMG ────────────────────────────────
echo "=== Step 8/10: Sign DMG ==="
codesign --force --sign "$SIGNING_IDENTITY" --keychain "$BUILD_KEYCHAIN" --timestamp "$DMG_PATH"
echo "DMG signed."

if $SKIP_NOTARIZE; then
    echo "=== Step 9/10: Notarize + staple DMG (SKIPPED) ==="
else
    echo "=== Step 9/10: Notarize + staple DMG ==="
    xcrun notarytool submit "$DMG_PATH" \
        --key "$BUILD_DIR/AuthKey_${API_KEY_ID}.p8" \
        --key-id "$API_KEY_ID" \
        --issuer "$API_ISSUER_ID" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    echo "DMG notarized and stapled."
fi

# ─── Step 10/10: Sparkle EdDSA sign + generate appcast ──────────────────────
echo "=== Step 10/10: Generate appcast.xml ==="

SPARKLE_PRIVATE_KEY=$(cat "$SPARKLE_PRIVATE_KEY_FILE")
chmod +x "$SIGN_UPDATE"

RAW_OUTPUT=$(echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" "$DMG_PATH" --ed-key-file -)
ED_SIGNATURE=$(echo "$RAW_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_SIZE=$(stat -f%z "$DMG_PATH")

DOWNLOAD_URL="https://github.com/Aayush9029/petal/releases/download/v${VERSION}/${DMG_NAME}"

python3 "$SCRIPTS_DIR/generate-appcast.py" \
    --output "$PROJECT_DIR/appcast.xml" \
    --title "Petal" \
    --link "https://github.com/Aayush9029/petal" \
    --version "$VERSION" \
    --build "$BUILD_NUMBER" \
    --download-url "$DOWNLOAD_URL" \
    --ed-signature "$ED_SIGNATURE" \
    --length "$FILE_SIZE" \
    --minimum-system-version "15.0"

echo "appcast.xml generated at $PROJECT_DIR/appcast.xml"

# ─── Verification ────────────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="

echo -n "App signature: "
codesign --verify --deep --strict "$APP_PATH" && echo "OK" || echo "FAILED"

echo -n "DMG signature: "
codesign --verify "$DMG_PATH" && echo "OK" || echo "FAILED"

if ! $SKIP_NOTARIZE; then
    echo -n "Notarization ticket: "
    xcrun stapler validate "$DMG_PATH" && echo "OK" || echo "FAILED"

    echo -n "Gatekeeper: "
    spctl --assess --type open --context context:primary-signature "$DMG_PATH" && echo "OK" || echo "FAILED"

    "$SCRIPTS_DIR/verify-notarization.sh" --app "$APP_PATH" --require-aria2c
fi

echo -n "EdDSA signature: "
[[ -n "$ED_SIGNATURE" ]] && echo "OK ($ED_SIGNATURE)" || echo "FAILED"

echo -n "Appcast version: "
grep -q "<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>" "$PROJECT_DIR/appcast.xml" && echo "OK" || echo "FAILED"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Done ==="
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "Output: $DMG_PATH ($DMG_SIZE)"
echo ""
echo "Next steps:"
echo "  1. gh release create v${VERSION} ./${DMG_NAME} --title 'v${VERSION}' --notes 'Release notes'"
echo "  2. git add appcast.xml && git commit -m 'Update appcast.xml for v${VERSION}' && git push"
