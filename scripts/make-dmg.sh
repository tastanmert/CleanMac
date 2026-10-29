#!/bin/zsh
# Arkadaşlarla paylaşmak için build/CleanMac.dmg üretir (evrensel; yerel geliştirici sertifikasıyla imzalı).
set -euo pipefail
cd "$(dirname "$0")/.."

# Yerel kurulumla aynı imza (Apple Development, yoksa ad-hoc): kendini güncelleyen uygulamanın kimliği
# sürümden sürüme aynı kalır, Tam Disk Erişimi gibi izinler güncellemeden sonra da geçerli olur.
./scripts/build-app.sh build/stage-install >/dev/null
APP="build/stage-install/CleanMac.app"
codesign --verify --deep --strict "$APP"

STAGE="build/dmg"
rm -rf "$STAGE" build/CleanMac.dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/İlk açılış.txt" <<'T'
CleanMac'i Uygulamalar klasörüne sürükle.

İlk açılışta macOS "doğrulanamadı" diyebilir (uygulama Apple noter onayından geçmedi).
Çözüm: CleanMac'i bir kez açmayı dene, sonra Sistem Ayarları > Gizlilik ve Güvenlik'te
aşağıdaki "Yine de Aç" düğmesine bas (macOS 15 ve sonrasında sağ tık > Aç artık yetmiyor).
Olmazsa Terminal'de şunu çalıştır:
  xattr -dr com.apple.quarantine /Applications/CleanMac.app

Her şey Çöp'e taşınır; Çöp'ü boşaltana kadar geri alabilirsin.
T
hdiutil create -volname "CleanMac" -srcfolder "$STAGE" -ov -format UDZO build/CleanMac.dmg >/dev/null
echo "Hazır: build/CleanMac.dmg ($(du -h build/CleanMac.dmg | cut -f1))"
