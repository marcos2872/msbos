# MyOS — tema consistente niri + Noctalia (paleta macOS dark).
#
# O Noctalia só pinta o shell; apps GTK/Qt/Electron leem estas variáveis.
# Cores de referência (assets/noctalia/palettes/macOS.json): fundo #0B0B0D,
# texto #F5F5F7, acento #5E5CE6.
#
# Cursor único (mesmo do settings.ini/dconf): Adwaita 24px no compositor e
# nos apps. Sem isto o niri usa o default do sistema e diverge do GTK.
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
#
# Qt (ex.: ONLYOFFICE): sem isto o Qt cai no estilo claro nativo.
# O qt6ct/qt5ct lê ~/.config/qt6ct/qt6ct.conf (estilo Fusion escuro do MyOS).
# shellcheck disable=SC2046
if command -v qt6ct >/dev/null 2>&1; then
  export QT_QPA_PLATFORMTHEME=qt6ct
elif command -v qt5ct >/dev/null 2>&1; then
  export QT_QPA_PLATFORMTHEME=qt5ct
fi
