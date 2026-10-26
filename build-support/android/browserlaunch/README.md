# Native Android browser admission

`native-run.v` uses this module only when both
`VINIX_ANDROID_BROWSER_MANIFEST` and `VINIX_ANDROID_BROWSER_MANIFEST_SHA256`
are set by the root launch administrator. Ordinary launches start no browser.
An explicit but invalid configuration fails the launch.

The account registry must already admit the APK and the selected Unix UID/GID.
The manifest must attest an **exclusive**, provisioned app principal: UID/GID
10000–19999, with no other launcher or account sharing that principal. The
launcher checks the selected identity and app data path against that attestation;
administrators remain responsible for exclusive provisioning. Do not enable
this feature for legacy callers that can launch arbitrary code under that UID.

The UTF-8 manifest uses literal tabs between fields and a final newline. All
hashes are lowercase SHA-256. Example structure (replace every `SHA256`):

```text
vinix-android-browser-launch-v1
exclusive-principal	10042	10042	/var/lib/vinix/apps/10042
root	/opt/vinix/browser
loader	lib/ld-musl-aarch64.so.1
engine	bin/webview-engine
xvfb	usr/bin/Xvfb
libraries	lib:usr/lib
xkb	usr/share/X11/xkb
fonts	usr/share/fonts/misc
fontconfig	etc/fonts/fonts.conf
file	SHA256	lib/ld-musl-aarch64.so.1
file	SHA256	bin/webview-engine
file	SHA256	usr/bin/Xvfb
file	SHA256	etc/fonts/fonts.conf
external	SHA256	/lib/ld-musl-aarch64.so.1
external	SHA256	/usr/bin/xkbcomp
external	SHA256	/usr/bin/bwrap
external	SHA256	/usr/libexec/webkitgtk-6.0/WebKitWebProcess
external	SHA256	/usr/libexec/webkitgtk-6.0/WebKitNetworkProcess
external	SHA256	/usr/libexec/webkitgtk-6.0/WebKitGPUProcess
```

Add a `file` entry for **every** regular file in the browser root, including
libraries, fonts and XKB data. The root and every ancestor must be root-owned
and not writable by group/other; every file must be root-owned, read-only,
regular, and have one hard link. Symlinks, special files and unlisted files
are rejected. Provision a flattened closure, rather than pointing this at an
ordinary writable package tree. Fixed-path subprocesses and their ELF
interpreter have separate mandatory pins. Use WebKitGTK 2.48.1 / GTK 4.24.1
matching `webviewengine`; the runtime must provide the namespaces and other
kernel facilities required by WebKit's sandbox. There is no sandbox-disable
fallback. Any inherited `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS` entry is
rejected, regardless of its value.

Manifest and root descriptors survive the credential drop with CLOEXEC and
detect replacement before the first browser command. The manifest digest and
complete closure are checked again after the lazy wait. Keep the deployment
immutable throughout execution: subsequent executable and library opens still
use absolute paths, so this does not isolate a deployment from a concurrent
root administrator replacing it.

Only after the irreversible UID/GID/group/capability drop does the launcher
create the Unix socketpair. ART receives `VINIX_ANDROID_WEBVIEW_FD`; its native
client must claim it eagerly and set CLOEXEC. The supervisor preserves queued
VBR1 bytes, and starts no engine or Xvfb until a command arrives. It closes all
unrelated inherited descriptors. Client EOF stops engine/Xvfb process groups;
an intermediate process is reaped before ART exec so the supervisor does not
leave an Android child zombie.

The profile is `ANDROID_APP_DATA_DIR/webview`, canonical, app-owned and mode
0700 beneath protected ancestors. Each session has private temporary HOME,
runtime files, log and a mode-0600 MIT cookie authority. Xvfb listens without
TCP. The supervisor checks its kernel peer PID/UID/GID before disclosing the
cookie, tests acceptance of the correct cookie and rejection of a wrong one,
then launches `webview-engine --control-fd N --profile ABS`. The helper receives
an explicitly constructed environment containing only browser closure library
paths, never ART's preload, Bionic paths or service/WS authority descriptors.
Startup failures close the channel and report through the original stderr.

Run focused host tests with:

```sh
/Users/alex/code/v/v -w -n -cc cc -path 'build-support/android|@vlib|@vmodules' test build-support/android/browserlaunch
```

The tests cover parser mutations, metadata/path admission, descriptor cleanup,
lazy command preservation, EOF, profile modes, authority creation, peer
rejection before cookie disclosure, sanitized environment and process cleanup.
The queued-command/HUP rule is Linux-specific; macOS exercises ordinary EOF.
X11 readiness uses a nonblocking connector with descriptor cleanup on every
failure and one absolute setup deadline, including byte-dribbling peers.
Successful root provisioning, WebKit sandbox startup and Google authentication
still require runtime evidence; host tests do not establish account login.
