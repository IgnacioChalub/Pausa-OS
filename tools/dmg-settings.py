# Ventana del instalador para dmgbuild (la usa package.sh).
# Las posiciones de los íconos coinciden con las del fondo (tools/make-dmg-background.swift).
app = defines["app"]
background_dir = defines["background_dir"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "assets/AppIcon.icns"            # ícono del disco montado
background = f"{background_dir}/background.tiff"

window_rect = ((200, 140), (640, 400))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
show_icon_preview = False
icon_size = 112
text_size = 13
icon_locations = {"Pausa.app": (180, 205), "Applications": (460, 205)}
hide_extensions = ["Pausa.app"]
