#!/bin/zsh
# Lists interface texts that have no English translation in Localization/en.lproj/Localizable.strings.
# The compiler reports every Text("…") / String(localized: "…") key; enum labels shown with `.localized` are listed in
# EXTRA_KEYS below. Exit status 1 when something is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null

python3 - "$OUT" <<'PY'
import glob, json, subprocess, sys
EXTRA_KEYS = ["Diğer", "Ev klasörü", "Boyut", "Ad", "Tarih", "Tümü", "Arşivler", "Belgeler", "Videolar", "Görseller", "Ses",
              "Her zaman", "1 aydan eski", "6 aydan eski", "1 yıldan eski"]
keys = set(EXTRA_KEYS)
for f in glob.glob(sys.argv[1] + "/*.stringsdata"):
    for table in json.load(open(f)).get("tables", {}).values():
        keys.update(e["key"] for e in table)
keys.discard("")
plist = subprocess.run(["plutil", "-convert", "json", "-o", "-", "Localization/en.lproj/Localizable.strings"],
                       capture_output=True, text=True, check=True).stdout
english = json.loads(plist)
missing = sorted(keys - english.keys())
for key in missing: print(f'"{key}" = "";')
print(f"{len(keys)} metin, {len(missing)} çevirisiz.", file=sys.stderr)
sys.exit(1 if missing else 0)
PY
