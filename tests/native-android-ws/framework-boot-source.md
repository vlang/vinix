# Framework visibility for isolated module loaders

GMS's Cronet module loader cannot resolve `android.content.Context` even though
the framework contains it. Its platform parent is the topmost boot loader;
the native runtime previously supplied the framework only through the system
class path. The complete caller trace is retained in
`S/gms-cronet-classloader-audit-2026-11-03-r1`, where
`S=/Users/alex/.local/state/vinix/android`.

The native bootstrap now sets an explicit boot class path: the pinned runtime's
ten existing libraries in their original order, then the API JAR.
The APK stays in `atl.app.class.path`. The original system class path remains
intact because ATLPaths parses its API-JAR prefix and the resource-only
framework APK must remain available there. The two-method SDK companion uses
the system loader in Resources.getSystem and ATLLoadedApp.loadFromPath to
preserve framework/app resource discovery while platform class identity comes
from the shared boot parent.

`framework-res.apk` contains no DEX and is deliberately excluded from the boot
path. ART derives boot-resource entries from loaded DexFiles, so adding this
APK to the boot string would not make its manifest boot-visible. The API JAR
has no AndroidManifest.xml; system resource lookup consequently retains one
framework manifest, followed by each app's own manifest through its app loader.

JNI startup now uses its existing qualified absolute library path through
Runtime.load(String, ClassLoader). BootClassLoader does not implement library
name lookup, so the old Runtime.loadLibrary overload would fail after moving
View to the boot path. The pinned ART implementation normalizes that loader to
its native boot identity before associating the library.

The new path-formatting helper rejects null buffers, zero capacity and snprintf
truncation. Its 64 KiB stack buffer covers eleven entries with a 4,095-byte root;
that boundary applies only to this helper, not to other unchanged startup
buffers. Both startup buffers remain alive through VM creation. Normal and TLS
option counts are 13 and 15 within the unchanged sixteen-slot allocation. No
retained allocation or new asynchronous lifetime is introduced.

Exact primary and frozen SDK/source evidence remains at
`S/boot-classpath-core-audit-2026-11-03-r1`. It records the original ten-library
order, loader/resource/JNI contracts, complete source files and artifact
checksums. The primary runtime commit is
`e78bf68917bcaaf58fef3960cd88793b3b7f39cc` from the deployed ART manifest.
`SHA256SUMS` hashes to
`e5bc6618969dec60719fa91a49ae4faaee1aacb84c5e740cafb1a142f3592163`.
Its source-only `audit.md` hashes to
`7190ec1b88d33657ea64209ef6070d345679495529f2bb152c23ef712c759095`.
The exact native before sources come from the qualified WebView native r2;
source parent for this audit is `612beac7a`. Independent revised native source
review passed. The source-bound host checker passed the complete two-file delta,
17 mutation controls, 27 actual-helper cases and two compiled boundary controls.
Evidence is at `S/framework-boot-source-check-2026-11-03-r2`; receipt SHA-256 is
`2b1d44920aa607e0b62f392915657795933eca95e199dbf2770ecc020cba9c1b`.
Guard and child exited zero with complete cleanup in 3.673 seconds at
205,864,960 bytes sampled RSS, 7,577,600 bytes shared growth and zero swaps.
The first checker's compiler-input bound failure remains in the separate r1
bundle. Complete SDK/native production and the signed ARM class-loader
regression remain separate qualification steps.
