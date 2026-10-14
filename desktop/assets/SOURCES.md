# Application icons

Every `.qoi` file here is a lossless 512 × 512 RGBA
version of application artwork or a Vinix runtime pictogram. QOI is used so the
static Vinix desktop can decode the images without pulling a PNG library into
its framebuffer compositor.

- Chromium: [Chromium product logo](https://raw.githubusercontent.com/chromium/chromium/main/chrome/app/theme/chromium/product_logo.svg)
- Firefox: [Alpine Firefox ESR package](https://dl-cdn.alpinelinux.org/alpine/v3.22/community/aarch64/firefox-esr-140.12.0-r0.apk), `usr/share/icons/hicolor/scalable/apps/firefox-esr.svg`
- Blender: [Alpine Blender package](https://dl-cdn.alpinelinux.org/alpine/v3.21/community/aarch64/blender-4.3.0-r0.apk), `usr/share/icons/hicolor/scalable/apps/blender.svg`
- Minecraft: [official Minecraft client asset](https://resources.download.minecraft.net/f0/f00657542252858a721e715a2e888a9226404e35), `minecraft.icns` (1024 × 1024)
- DOOM: `M_DOOM` menu logo from a locally supplied DOOM WAD, decoded with its `PLAYPAL` palette and scaled without smoothing.
- Steam: [Valve's Steam installer package](https://cdn.fastly.steamstatic.com/client/installer/steam.deb), `usr/share/icons/hicolor/256x256/apps/steam.png`, resampled to 512 × 512
- VLC: [VideoLAN application icon](https://raw.githubusercontent.com/videolan/vlc/master/share/icons/256x256/vlc.png)
- VSCodium: [upstream stable Linux icon](https://raw.githubusercontent.com/VSCodium/vscodium/master/src/stable/resources/linux/code.png)
- Zed: [upstream application icon](https://raw.githubusercontent.com/zed-industries/zed/main/crates/zed/resources/app-icon@2x.png)
- Neovim: [upstream application icon](https://raw.githubusercontent.com/neovim/neovim/master/runtime/nvim.png)
- KeePassXC: [upstream application icon](https://raw.githubusercontent.com/keepassxreboot/keepassxc/develop/share/icons/application/256x256/apps/keepassxc.png)
- Telegram: [upstream 512px icon](https://raw.githubusercontent.com/telegramdesktop/tdesktop/dev/Telegram/Resources/art/icon512.png)
- Discord: [Font Awesome brand artwork](https://raw.githubusercontent.com/FortAwesome/Font-Awesome/6.x/svgs/brands/discord.svg), CC BY 4.0, colored `#5865F2`
- Slack: [Slack's multicolor brand icon](https://a.slack-edge.com/80588/marketing/img/meta/slack_hash_256.png)
- Spotify: [Simple Icons brand artwork](https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/spotify.svg), CC0, colored `#1DB954`
- OBS Studio: [upstream 512px application icon](https://raw.githubusercontent.com/obsproject/obs-studio/master/frontend/cmake/linux/icons/obs-logo-512.png)
- iOS runtime: original Vinix phone pictogram, representing the native compatibility layer.
- Terminal, Settings, Activity Monitor, Calculator, Disk Usage, Text Editor, Files,
  Clock, Calendar, and Capture: user-provided 1254 × 1254 PNG artwork,
  preserved without visual edits before QOI encoding.

The vectors were rasterized at 512 × 512 before lossless QOI encoding, which
keeps the desktop’s 1× and 2× shortcut, menu, taskbar, and window-state icons
sharp.

The first-boot additions were fetched on 2026-10-14. SHA-256 of the unmodified
source bytes, before color assignment/rasterization and QOI conversion:

| Icon | Source SHA-256 |
| --- | --- |
| VLC | `a1ccd4a5006713dc65ad84f41281ce732c23533555debc4e71f6457bb26b8fa1` |
| VSCodium | `056d737aec55a8001e073ae8597a43f884732d2427f51880d6ceba0ae91d2465` |
| Zed | `113ef50d1d7f5dfddf5c0fc00592da449043c3b0ace3f6f68c80c134b816e9bc` |
| Neovim | `e6e68a31327f67c24f5fcbea175b13862275363c2e7b0a5999781104c8658c16` |
| KeePassXC | `517e021ae33591d41139ac187d84b3d6a64564de4942858bf8d789f25c17f9c5` |
| Telegram | `e297771c75bd2f81d637a3234f83568be62092f67d16946be23895fa92fa7119` |
| Discord | `5411e43669f6fd0613413ec9f4e605fde9331d112d168da6a228994df25a066d` |
| Slack | `fff0ab554a4dc202afd1cbf2033a3ad340cf25b4991035d2d31407b5e7e4c366` |
| Spotify | `b9ec9bec7769c35643981586d6ea0d675aaf3871b32f8a291bcac7a87fff0bc1` |
| OBS Studio | `043b35b8ebb6238d0dd9171c5437635f6266825ce028d2f79363f705cf7d6be5` |

Artwork was fetched and converted with V tooling invoking curl and ImageMagick;
SVGs were rasterized at sufficient density before scaling. PNG source colors
and proportions are preserved. The icon tests pin decoded ARGB hashes to check
the embedded icons even when no installed icon directory exists.
