#!/usr/bin/env bash
set -euo pipefail

echo "== iOS Preflight =="
echo "Repo: ${GITHUB_REPOSITORY:-local}"
echo "SHA:  ${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    fail "Missing required file: $path"
  fi
}

# Basic repo sanity
require_file "fastlane/Fastfile"
require_file "ios/project.yml"
require_file "ios/Resources/Info.plist"
require_file "ios/Resources/LaunchScreen.storyboard"
require_file "ios/Resources/ModelCatalog.json"
require_file "ios/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
require_file "ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-60@2x.png"
require_file "ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-76@2x.png"
require_file "ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
require_file "ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-ipad-76@1x.png"

# Validate ModelCatalog.json is valid JSON
python3 - <<'PY'
import json
from pathlib import Path

p = Path("ios/Resources/ModelCatalog.json")
data = json.loads(p.read_text(encoding="utf-8"))
if not isinstance(data, dict) or "items" not in data or not isinstance(data["items"], list):
    raise SystemExit("ModelCatalog.json must be an object with an 'items' array")
PY

# Ensure Google Sign-In is configured (no placeholders)
python3 - <<'PY'
import plistlib
import sys
from pathlib import Path

p = Path("ios/Resources/Info.plist")
with p.open("rb") as f:
    pl = plistlib.load(f)

client_id = pl.get("GIDClientID")
if not client_id or "REPLACE_WITH" in str(client_id):
    print("Missing/placeholder GIDClientID in ios/Resources/Info.plist")
    sys.exit(1)

url_types = pl.get("CFBundleURLTypes") or []
has_google_scheme = False
for t in url_types:
    schemes = t.get("CFBundleURLSchemes") or []
    for s in schemes:
        if isinstance(s, str) and s.startswith("com.googleusercontent.apps."):
            has_google_scheme = True
            break
    if has_google_scheme:
        break

if not has_google_scheme:
    print("Missing Google reversed client id URL scheme (com.googleusercontent.apps.*) in ios/Resources/Info.plist")
    sys.exit(1)
PY

# Make sure we aren't using removed GoogleSignIn APIs (v8+)
if grep -n "sharedInstance\\.addScopes" ios/Core/Sync/Drive/DriveAuthManager.swift; then
  fail "DriveAuthManager uses removed API 'GIDSignIn.sharedInstance.addScopes'. Use 'result.user.addScopes(...)' instead."
fi

# MainActor isolation: default args are evaluated outside actor context
if grep -n "auth: DriveAuthManager = DriveAuthManager()" ios/Core/Sync/Drive/DriveSyncService.swift; then
  fail "DriveSyncService init uses a MainActor default arg. Use an optional param and create inside init."
fi

# Swift Package archiving: don't override Info.plist globally via xcargs
if grep -n "INFOPLIST_FILE=" fastlane/Fastfile; then
  fail "fastlane/Fastfile must not set INFOPLIST_FILE via xcargs (breaks SPM targets)."
fi
if grep -n "GENERATE_INFOPLIST_FILE=" fastlane/Fastfile; then
  fail "fastlane/Fastfile must not set GENERATE_INFOPLIST_FILE via xcargs (breaks SPM targets)."
fi

# Prevent committing large .gguf model weights. Allow llama.cpp vocab ggufs.
disallowed_gguf="$(git ls-files '*.gguf' | grep -vE '^ios/llama/models/ggml-vocab-.*\\.gguf$' || true)"
if [ -n "$disallowed_gguf" ]; then
  echo "Disallowed tracked .gguf files (models must not be committed):"
  echo "$disallowed_gguf"
  exit 1
fi

# Prevent accidental key/cert commits.
tracked_secrets="$(git ls-files | grep -E '\\.(p8|p12|mobileprovision)$' || true)"
if [ -n "$tracked_secrets" ]; then
  echo "Tracked key/cert files detected (should not be committed):"
  echo "$tracked_secrets"
  exit 1
fi

echo "Preflight OK"
