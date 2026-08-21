#!/bin/sh
set -eu

: "${DEVELOPER_ID_APPLICATION:?Set Developer ID Application identity}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set notarytool keychain profile}"
: "${SPARKLE_PRIVATE_KEY_FILE:?Set Sparkle EdDSA private key path}"

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${1:?Usage: package-release.sh VERSION}
dist="$root/dist/$version"
archive="$dist/Piqo.xcarchive"
app="$archive/Products/Applications/Piqo.app"
mkdir -p "$dist"
"$root/scripts/fetch-sidecar.sh"
swift package --package-path "$root" resolve

xcodebuild -project "$root/Piqo.xcodeproj" -scheme Piqo -configuration Release \
  -archivePath "$archive" archive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  SPARKLE_EDDSA_PUBLIC_KEY="${SPARKLE_EDDSA_PUBLIC_KEY:?Set Sparkle public key}"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app/Contents/Helpers/piqo-server"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
xcrun notarytool submit "$app" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$app"
hdiutil create -volname Piqo -srcfolder "$(dirname "$app")" -ov -format UDZO "$dist/Piqo-$version.dmg"
"$root/.build/checkouts/Sparkle/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$dist"
