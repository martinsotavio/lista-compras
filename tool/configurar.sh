#!/bin/sh
# Permissões que o `flutter create` não põe (o projeto já vem com elas; serve para recriar as pastas).
#   sh tool/configurar.sh
# Pode rodar de novo sem estragar nada (confere antes de acrescentar). Funciona no Linux e no Mac.
set -e
cd "$(dirname "$0")/.."
# sed -i do Mac (BSD) pede '' e o do Linux (GNU) não aceita: esta função serve para os dois.
sedi() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }

# ---- Android: internet no build de release (o debug já tem) e abrir o app de e-mail (convites) ----
M=android/app/src/main/AndroidManifest.xml
if [ -f "$M" ]; then
  grep -q "android.permission.INTERNET" "$M" || sedi 's#<application#<uses-permission android:name="android.permission.INTERNET" />\
    <application#' "$M"
  grep -q 'android:scheme="mailto"' "$M" || sedi 's#<queries>#<queries>\
        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>#' "$M"
  echo "Android: internet e e-mail configurados."
fi

# ---- iOS: câmera, fotos e iOS 15 (o Firebase pede). O Info.plist só se edita direito no Mac (PlistBuddy). ----
PB=/usr/libexec/PlistBuddy
if [ -d ios ]; then
  if [ -x "$PB" ]; then
    $PB -c "Add :NSCameraUsageDescription string Para ler o código de barras e fotografar o que acabou." ios/Runner/Info.plist 2>/dev/null || true
    $PB -c "Add :NSPhotoLibraryUsageDescription string Para escolher a foto de um produto que acabou." ios/Runner/Info.plist 2>/dev/null || true
  fi
  sedi "s/^# platform :ios, '[0-9.]*'/platform :ios, '15.0'/; s/^platform :ios, '[0-9.]*'/platform :ios, '15.0'/" ios/Podfile
  echo "iOS: permissões e iOS 15 configurados."
fi
exit 0
