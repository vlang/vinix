# Roblox's Windows Player under Wine

`run.py` starts the unchanged Windows client on ARM64 Vinix and records how
far it gets. It fetches the current deployment from Roblox's own CDN, checks
every package against the deployment's manifest, unpacks them into the layout
the Windows installer produces, and boots Vinix under QEMU/HVF with only what
the client needs: the x86-64 translator, Wine, Xvfb and the X11 input bridge.
A test init runs Wine's Win64 smoke test, then `RobloxPlayerBeta.exe` on a
private display, and watches it for `--seconds`.

```sh
./scripts/build-x86-translation-aarch64.sh
python3 tests/roblox-windows/run.py
python3 tests/roblox-windows/run.py --strace
```

It needs the X11 and userland layers (`build-aarch64-x11`,
`build-aarch64-userland`) and a built kernel. `--repo` names another checkout
to take the layers and `scripts/run-aarch64.sh` from, `--kernel-dir` another kernel,
`--translation` another stage of `scripts/build-x86-translation-aarch64.sh` and
`--version` a particular deployment. Everything is kept below `--work`
(`build/roblox-windows`): the downloaded packages, the staged client,
`vinix.log` with the serial console, and `uploads/` with Wine's log, any log
the client wrote for itself and the display as PNG files. Nothing of Roblox's
is stored in the repository.

The test passes when the client is still running at the end of the
observation and has drawn something. It does not pass today, and
[docs/roblox.md](../../docs/roblox.md) says why: the client's anti-tamper
layer makes Windows system calls with the `syscall` instruction, which reach
Vinix as Linux system calls. `--strace` reports those calls instead of Wine's
log, and stops the client after the first 200. `--winedebug=+seh,err+all`
shows the access violation that follows the first of them.

`--shell` boots the same machine with a shell on its console instead of
starting the client. Lines written to `shell.in` in the work directory are
typed at that shell, the transcript is `vinix.log`, the upload port stays
open for `wget --post-file`, and a line containing `poweroff-test` ends the
run. `/opt/roblox-test/config.sh` holds the client's path.

A translation stage older than its build script fails before the client is
reached: Wine's smoke test segfaults when the stage lacks the links the
script now makes inside the x86-64 root. Rebuild the stage in that case.
