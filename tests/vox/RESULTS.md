# Native Vox desktop check — 2026-11-08

Vox's original `main.v` runs as an ARM64 application through UI2's native Vinix
IPC and shared surfaces. The complete packaged dependency closure contains no
X11, XCB, Wayland or GTK libraries. libglvnd was built with X11 and GLX disabled.

The desktop source base is Vinix `06d6c33c9413d80dde7303cbcc8e3ce3f33c5644`,
with this port's application registration. Capture-time checkout identities
were Vox `f9617292164d4a1080f1d9e7b15466ed058ba5dc` and UI2
`c807d7651970a92be01c759363625031629c655c`. The shared Vox checkout changed
during development; those HEADs alone do not identify all build inputs. The
archive retains generated C, the staged source overrides, source patches,
runtime receipt and the complete guest inventory. Its port source snapshot is
`b617d0a05177b43859f132f4f8998616e1f5c165b56b44dfdcdc1a7d77d81553`
(SHA-256), taken before this report was written.

Validation passed:

- Twelve focused checks on the host and the same ARM64 checks in Vinix,
  covering rendering, arena lifetimes, shared-buffer ownership and worker FDs.
- The original browser's guest smoke: JavaScript DOM mutation, click listeners,
  native wheel routing and ordinary element wheel listeners.
- A fresh desktop process navigated through Ctrl-L to the local HTML fixture.
  Clicking its actual button changed the DOM to “JavaScript click received on
  Vinix,” visible in the captured QEMU framebuffer.
- The evidence recorder accepted seven live samples at 15-second intervals,
  with no fatal guest markers. Free system memory increased by 7,632 KiB over
  the final 45 seconds. This is a short functional guard, not leak qualification.
- V formatting verification and `git diff --check`.

Executable SHA-256:
`541046a1cf9f5aa8ae03f194178ea2383f7b282baa49d98e88c6e084cb8f96b2`.
Generated C SHA-256:
`3d593bcc3671b8920f25a8eb2b7c14d97bb957940513fc549e97a24db393d6aa`.
Screenshot SHA-256:
`0293a80ec270d8a25c1b256f56720803b52cf1a69c57fca6c5368ffcc311d8db`.

Preserved evidence directory:
`/Users/alex/.local/state/vinix-vox/validated-20261108-541046a1/`.
It contains `vox-vinix-desktop.png`, `receipt.tsv` and the complete
`vox-native-evidence.tar.gz`, whose SHA-256 is
`8891ae84c77aa1f0497dacba445b325de7107fc2b0cdae3258bdd6ec87562c91`.
The installable runtime is `/Users/alex/.local/state/vinix-vox/staging`.

The VM booted the retained PTY kernel, SHA-256
`246ce2e5c33f0941870cb76d47d5c095575503df405a3de9243bdc1d935e4771`.
This run does not validate concurrent kernel changes in the checkout.
The CPU renderer uses an unoptimized development build; clipboard, IME,
hardware graphics, detached process tabs and the internal window controls
remain unimplemented. See [the workflow](README.md) for reproduction and limits.
