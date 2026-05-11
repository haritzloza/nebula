# wallpapers

## Pack incluido: `aesthetic/` (D3Ext/aesthetic-wallpapers · MIT)

Es un submódulo git que se clona durante `install.sh` cuando seleccionas la opción
"wallpapers". ~200 imágenes anime / aesthetic / ultrawide con licencia MIT.

Para clonarlo manualmente sin el instalador:

```bash
git submodule update --init --recursive
# o:
git clone --depth=1 https://github.com/D3Ext/aesthetic-wallpapers.git wallpapers/aesthetic
ln -sfn "$PWD/wallpapers/aesthetic/images" ~/Pictures/wallpapers
```

## Tus propios wallpapers

Echa los tuyos en `~/Pictures/wallpapers/` (carpeta o symlink) y el script
[wallpaper-cycle.sh](../hypr/.config/hypr/scripts/wallpaper-cycle.sh) los detectará.
`SUPER+W` cicla. Con theming dinámico activo, `SUPER+W` además regenera la paleta
de colores con `matugen` y la aplica a Waybar/Rofi/Kitty/Hyprland.

## Otras fuentes (no incluidas por licencia)

Si quieres más variedad anime/lofi, hay buenos repos pero **sin licencia clara** —
úsalos solo para tu uso personal, no los redistribuyas en tu fork:

- `dharmx/walls` — anime + evangelion + lofi
- `orangci/walls-catppuccin-mocha` — 500+ curados Catppuccin
- `wallhaven.cc` — API con tags

El script [scripts/wallhaven-fetch.sh](../scripts/wallhaven-fetch.sh) descarga
reproducible con tag `catppuccin+anime`, resolución mínima 2560x1440.
