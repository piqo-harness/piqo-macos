#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
lock="$root/Sidecar.lock.json"
version=$(/usr/libexec/PlistBuddy -c 'Print :version' "$lock" 2>/dev/null || /usr/bin/plutil -extract version raw "$lock")
url=$(/usr/bin/plutil -extract archive_url raw "$lock")
expected=$(/usr/bin/plutil -extract sha256 raw "$lock")
test "$expected" != "REPLACE_WITH_RELEASE_SHA256"

stage="$root/.build/sidecar"
archive="$stage/piqo-server.tar.gz"
rm -rf "$stage"
mkdir -p "$stage/unpacked"
/usr/bin/curl --fail --location --proto '=https' --tlsv1.2 "$url" -o "$archive"
actual=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
test "$actual" = "$expected" || { echo "sidecar SHA-256 mismatch" >&2; exit 1; }
/usr/bin/tar -xzf "$archive" -C "$stage/unpacked"
helper=$(/usr/bin/find "$stage/unpacked" -type f -name piqo-server -perm -111 -print -quit)
test -n "$helper" || { echo "piqo-server not found in v$version artifact" >&2; exit 1; }
/bin/cp "$helper" "$stage/piqo-server"
/bin/chmod 755 "$stage/piqo-server"
