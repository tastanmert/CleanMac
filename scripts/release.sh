#!/bin/zsh
# Publishes a new CleanMac version in one go; installed copies offer it in the app (checked at launch and daily).
#   ./scripts/release.sh 1.4.1 "Short note for this release"
# Tests, checks translations, builds the DMG, commits and tags, sends the code to the public repository and
# creates the GitHub release there (and on the team repository, whose older builds still look there).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version, e.g. 1.4.1}"
NOTES="${2:-}"
[[ -z "$(git status --porcelain)" ]] || { echo "Çalışma ağacı temiz değil; önce commit et." >&2; exit 1; }

CURRENT="$(sed -n 's#.*<key>CFBundleShortVersionString</key><string>\(.*\)</string>#\1#p' scripts/build-app.sh)"
BUILD="$(sed -n 's#.*<key>CFBundleVersion</key><string>\(.*\)</string>#\1#p' scripts/build-app.sh)"
sed -i '' "s#<key>CFBundleShortVersionString</key><string>$CURRENT</string>#<key>CFBundleShortVersionString</key><string>$VERSION</string>#; s#<key>CFBundleVersion</key><string>$BUILD</string>#<key>CFBundleVersion</key><string>$((BUILD + 1))</string>#" scripts/build-app.sh

swift test >/dev/null || { git checkout scripts/build-app.sh; echo "Testler geçmedi." >&2; exit 1; }
./scripts/check-localization.sh >/dev/null || echo "Uyarı: çevirisi eksik metinler var (./scripts/check-localization.sh)." >&2
./scripts/build-app.sh >/dev/null
./scripts/make-dmg.sh >/dev/null

git commit -qam "Sürüm $VERSION"
git tag "v$VERSION"
git push -q && git push -q origin "v$VERSION"
./scripts/publish-public.sh "CleanMac $VERSION"

BODY="$NOTES

Universal (Apple Silicon + Intel), macOS 15 or later. Installed copies update from the app; new installs: drag CleanMac to Applications, and if macOS blocks the first launch use System Settings › Privacy & Security › Open Anyway."
gh release create "v$VERSION" build/CleanMac.dmg --repo tastanmert/CleanMac --target main --title "CleanMac $VERSION" --notes "$BODY"
gh release create "v$VERSION" build/CleanMac.dmg --repo HMDevTR/CleanMac --title "CleanMac $VERSION" --notes "$BODY" >/dev/null || true
echo "Yayında: https://github.com/tastanmert/CleanMac/releases/tag/v$VERSION"
