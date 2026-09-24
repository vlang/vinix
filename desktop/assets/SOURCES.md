# Application icons

Every `.qoi` file here is a lossless 512 × 512 RGBA
versions of the respective official app artwork. QOI is used solely so the
static Vinix desktop can decode the images without pulling a PNG library into
its framebuffer compositor.

- Chromium: [Chromium product logo](https://raw.githubusercontent.com/chromium/chromium/main/chrome/app/theme/chromium/product_logo.svg)
- Firefox: [Alpine Firefox ESR package](https://dl-cdn.alpinelinux.org/alpine/v3.22/community/aarch64/firefox-esr-140.12.0-r0.apk), `usr/share/icons/hicolor/scalable/apps/firefox-esr.svg`
- Blender: [Alpine Blender package](https://dl-cdn.alpinelinux.org/alpine/v3.21/community/aarch64/blender-4.3.0-r0.apk), `usr/share/icons/hicolor/scalable/apps/blender.svg`
- Minecraft: [official Minecraft client asset](https://resources.download.minecraft.net/f0/f00657542252858a721e715a2e888a9226404e35), `minecraft.icns` (1024 × 1024)
- Terminal, Settings, Activity Monitor, Calculator, VSpace, Text Editor, Files,
  Clock, Calendar, and Capture: user-provided 1254 × 1254 PNG artwork,
  preserved without visual edits before QOI encoding.

The vectors were rasterized at 512 × 512 before lossless QOI encoding, which
keeps the desktop’s 1× and 2× shortcut, menu, taskbar, and window-state icons
sharp.
