#!/usr/bin/env bash
# Abre o APK num celular virtual (emulador Android 14) e confere que ele NAO
# fecha sozinho, duas vezes seguidas. Guarda fotos da tela e o registro de
# falhas do Android em registro-emulador/. Se o app fechar, nao publica.
# Uso: ci/abrir-no-emulador.sh PACOTE ARQUIVO.apk
set -u
PKG="$1"
APK="$2"
OUT=registro-emulador
mkdir -p "$OUT"
FALHOU=0
adb wait-for-device
adb shell getprop ro.build.version.release | sed 's/^/Android /' > "$OUT/resumo.txt"
adb logcat -c || true
adb install -r "$APK" 2>&1 | tail -1 | tee -a "$OUT/resumo.txt"
for vez in 1 2; do
  adb shell am force-stop "$PKG" || true
  adb shell am start -W -n "$PKG/.MainActivity" 2>&1 | tail -3 | tee -a "$OUT/resumo.txt"
  sleep 25
  adb exec-out screencap -p > "$OUT/tela-$vez.png" || true
  if adb shell pidof "$PKG" > /dev/null 2>&1; then
    echo "abertura $vez: ABERTO" | tee -a "$OUT/resumo.txt"
  else
    echo "abertura $vez: FECHOU" | tee -a "$OUT/resumo.txt"
    FALHOU=1
  fi
done
adb logcat -d -b crash -v time > "$OUT/crash.txt" 2>/dev/null || true
echo "resultado: $([ $FALHOU = 0 ] && echo OK || echo FALHOU)" | tee -a "$OUT/resumo.txt"
exit $FALHOU
