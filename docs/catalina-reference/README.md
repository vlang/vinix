# macOS Catalina window reference

These captures are the visual source for Vinix's `macOS` desktop theme. They
were taken at the guest's native 1280×800 resolution from Apple's macOS
Catalina 10.15.7 recovery and installed systems (build 19H2) running under
QEMU. The recovery image was downloaded from Apple's signed recovery catalog
as product `2Z694-25616`, and its chunklist was verified before use.

The recovery media and installed virtual disk are deliberately not part of
this repository. Only the screenshots needed to review the theme are
committed.

## Captures

- `macos-utilities.png` — a standard AppKit window and disabled controls.
- `standard-titlebar.png` — the exact 594×22 standard window title bar.
- `disk-utility.png` — an active utility window with a centred title and
  integrated toolbar.
- `titled-titlebar.png` — the exact 926×22 titled title-bar crop.
- `traffic-lights-hover.png` — the native group-hover state.
- `traffic-lights-hover-crop.png` — a pixel-scale crop of that state.
- `erase-dialog.png` — an attached sheet and standard Catalina push buttons,
  text fields and pop-up controls.
- `standard-controls.png` — a native-size crop of those standard controls.
- `installer-welcome.png` — the Catalina installer window and centred title.
- `active-inactive-windows.png` — active Disk Utility beside an inactive
  standard Terminal window.
- `inactive-titlebar.png` — the exact 585×22 inactive title-bar crop.
- `installed-desktop.png` — the clean installed Catalina desktop in Light
  appearance after Setup Assistant completed.
- `installed-finder-window.png` — an active Finder window from the installed
  system, including its title bar, toolbar and sidebar controls.
- `installed-finder-traffic-lights-hover.png` — the same Finder window with
  Catalina's native group-hover traffic-light glyphs visible.
- `push-buttons-normal.png` — native-size regular and default Aqua push-button
  renditions from the installed system's shutdown dialog.
- `push-buttons-pressed.png` — the same controls while the regular button is
  held down; Catalina makes the pressed control blue and temporarily returns
  the former default control to its white rendition.

## Measured standard window chrome

All measurements are logical pixels at 1x.

| Part | Catalina value |
| --- | --- |
| Standard title bar | 22 px |
| Top highlight | 1 px, `#f3f3f3` |
| Active gradient | `#e4e4e4` to `#d1d1d1` over 20 px |
| Bottom divider | 1 px, `#ababab` |
| Inactive top / body / divider | `#fbfbfb` / `#f6f6f6` / `#d1d1d1` |
| Traffic-light visible diameter | 12 px |
| Leading inset | 8 px |
| Control centre spacing | 20 px |
| Control vertical inset | 5 px |
| Close fill / edge / glyph | `#ff5f57` / `#e0463e` / `#4d0000` |
| Minimize fill / edge / glyph | `#ffbd2e` / `#dea123` / `#995700` |
| Zoom fill / edge / glyph | `#28c940` / `#1aab29` / `#006500` |
| Inactive fill / edge | `#dcdcdc` / `#d1d1d1` |
| Disabled fill / edge | `#cfcfcf` / `#b8b8b8` |
| Standard window body | `#ececec` |
| Push-button visible bezel | 21 px |
| Regular button face / top / bottom edge | `#ffffff` / `#c9c9c9` / `#acacac` |
| Default button face | `#6ba0fb` to `#1164ff` |
| Pressed button face | `#4c8bfe` to `#0c55e5` |

The control images embedded in Catalina's AppKit `Assets.car` are 13×13
templates, while the visible coloured disc in the rendered 1x window is 12
pixels across. The close mark spans a 6×6 box. Disk Utility's zoom control uses
a 6×6 plus with two-pixel strokes; it is not the generic outlined square that
Vinix used before this reference was collected.

AppKit reveals all available control glyphs when the pointer is over any member
of the group. Vinix preserves that group-hover behaviour as well as the native
red-yellow-green order.

Regular push buttons do not have a hover-only visual change. On mouse-down,
Catalina uses its darker blue pressed rendition for either a regular or default
button. The source catalog includes distinct Normal, Pressed, Disabled and
Deeply Pressed images at both 1x and 2x; Vinix likewise samples the measured
scanlines at the physical backing-store resolution rather than enlarging 1x
corners into square pixel blocks.
