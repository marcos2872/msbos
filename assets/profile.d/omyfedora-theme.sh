# omyfedora — ambiente da sessão niri com os componentes de tema do KDE (Breeze).
#
# O omyfedora não impõe tema próprio: os apps usam o "Breeze Dark" do KDE. Este
# arquivo só aponta a sessão para os componentes certos:
#   • cursor breeze_cursors 24px (o mesmo do KDE; sem isto o niri usaria o
#     default do sistema e divergiria dos apps);
#   • platform theme Qt6 "kde" (plasma-integration): sem ele os apps Qt não
#     aplicam o estilo/cores do kdeglobals (Breeze/BreezeDark).
export XCURSOR_THEME=breeze_cursors
export XCURSOR_SIZE=24
if [ -f /usr/lib64/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so ]; then
  export QT_QPA_PLATFORMTHEME=kde
fi
