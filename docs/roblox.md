# Roblox APK on Vinix

The ARM64 desktop can launch Roblox's unchanged Android native engine with
[Cordial 0.23.2](https://github.com/luohoa97/cordial/releases/tag/v0.23.2).
Cordial supplies an Android linker, JNI and framework bridge for the APK's
`libroblox.so`. The x86-64 runtime runs through QEMU user translation and uses
Mesa's software GLES renderer. A native Weston 14 host runs its X11 backend
with Pixman inside the desktop's private Xvfb display, giving Cordial a Wayland
surface for the engine and its embedded web pages in a normal Vinix window.
This path is separate from the ART/DEX runtime described
in [Android APKs on Vinix](android.md).

Stage the runtime, then include it in an ARM64 desktop image. In addition to
the normal desktop build tools, the host needs Python 3, curl, zstd and
`unsquashfs` from squashfs-tools:

```sh
./build-roblox-aarch64.sh
./build-desktop-aarch64.sh --compact-initramfs --with-roblox
make -C kernel ARCH=aarch64 CC=clang LIMINE_MP=1
./run-desktop-aarch64.sh --no-build --mem=8192
```

The proprietary APK is not bundled or downloaded by the builder. Supply a
genuine Roblox Android APK containing `lib/x86_64/libroblox.so`, and copy it to
`$HOME/Roblox.apk` inside Vinix (`/root/Roblox.apk` for the default user). Open
**Roblox** from the desktop's Start menu or Quick Launch. Its
`run-roblox-client` command uses that path, or `VINIX_ROBLOX_APK` when set.
The launcher owns a private compositor and socket for each application, and
stops that compositor when Roblox exits or its window closes. Weston uses
Vinix's SysV shared memory through the app's Xvfb MIT-SHM extension.

From an existing X11 session, launch the complete desktop path at another local path:

```sh
VINIX_ROBLOX_APK=/root/Roblox-2.738.1397.apk run-roblox-client
```

From an existing Wayland session, `run-roblox /root/Roblox.apk` uses that
compositor. Its X11 fallback can render the landing screen, but Cordial cannot
attach its embedded Sign In, Join or Robux web pages to an X11 host. Use the
Wayland path to open those pages.

A split installation needs both the base APK containing assets and its
matching x86-64 native split:

```sh
VINIX_ROBLOX_APK=/root/base.apk run-roblox-client --native-apk /root/split_config.x86_64.apk
```

Additional arguments after these paths go to `cordial-run`; for example,
`--profile alternate` selects another Cordial profile. An ARM-only APK cannot
run with this staged x86-64 engine bridge.

The launcher extracts native libraries without changing them into
`$XDG_DATA_HOME/vinix/roblox/libraries/<native-apk-sha256>`, normally beneath
`$HOME/.local/share`. A completed extraction is published atomically and reused
for that exact APK build. `VINIX_ROBLOX_DATA_DIR` overrides this cache root and
the default profile root, which is `<data-root>/profiles`. Set
`CORDIAL_PROFILE_ROOT` to move profiles independently. Cordial's extracted
assets use `$XDG_CACHE_HOME/cordial/assets`, normally
`$HOME/.cache/cordial/assets`. With no desktop D-Bus session, the launcher
defaults to Cordial's file session store within the profile; these files use
owner-only permissions. An explicit
`CORDIAL_SECRET_STORE` value is preserved.

All downloaded runtime artifacts are pinned by SHA256. The private prefix
`/opt/vinix-roblox-x86_64` contains Cordial, glibc, its graphics and GUI
dependencies, and a genuine Noto CJK font. Native commands are installed at
`/usr/bin/run-roblox` and `/usr/bin/qemu-x86_64`. The builder retains upstream
license notices; Cordial is GPL-3.0-or-later and its
[matching source](https://github.com/luohoa97/cordial/tree/v0.23.2) is recorded
in `runtime-manifest.json`. `build-support/roblox/graphics.lock.json` records
the exact graphics package closure. `build-support/roblox/wayland.lock.json`
pins the native Weston package closure at `/opt/vinix-roblox-wayland`.
The default staging output is
`build-aarch64-roblox/x86_64/staging`; use the runtime builder's `--build-dir`
and the desktop builder's `VINIX_ROBLOX_STAGING` for another location.

The measured Vinix test launched the unchanged Roblox **2.738.1397** APK
(`com.roblox.client`, version code 3092) and rendered its real **Create Account /
Sign In** landing screen. The APK's signature and complete contents digest
were verified separately with Cordial's upstream APK verifier:

```text
APK SHA256: bbe00ae306cc251c4ea55b7a932d9c524ecb0d6d9203c2a6161bcf0fae792742
Signing certificate SHA256: 44932ea35a17a267372d71b54d1a0cb3da0dca5113e94406ae2fe18090ba1477
```

These hashes identify the tested APK, rather than a signature check performed
by `run-roblox` on every supplied file. Sign-in and gameplay have not been
verified on Vinix. Support is experimental; the pinned
[upstream release notes](https://github.com/luohoa97/cordial/releases/tag/v0.23.2)
also list a signed-in startup freeze and intermittent movement input issues.
