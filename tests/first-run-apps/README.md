# First-run software installs

Installs every app the "Choose your software" screen offers, in QEMU, the way
a user does, and fails unless each one installs:

```sh
tests/first-run-apps/run build-release/TAG/vinix-arm64.iso
tests/first-run-apps/run --timeout=600 build-release/TAG/vinix-amd64.iso
```

The test boots the ISO with a blank 16 GiB disk (`--disk=GIB`) and a network
card, waits for Vinix to install itself and show "Create your user", creates
the user, selects every app with the picker's keyboard controls and confirms.
The setup Terminal then installs them one by one. It writes each app's result
to the console as `vinix-setup: APP installed` or `vinix-setup: APP failed
(...)`, and `vinix-setup: done` at the end (desktop/app_selection.v); the test
reads those lines from the serial port. An app counts as installed only when
one of the paths by which the picker recognises it is executable afterwards.

The apps come from `desktop/app_selection_catalogue.v`, less the arm64-only
ones on amd64. arm64 runs under HVF; amd64 runs under TCG on an Apple Silicon
Mac, which is far slower, hence the longer timeout (minutes, default 300).

Everything the apps need comes from the network: Alpine's repositories, the
vendors' downloads, and the X11 bundle and iOS runtime of the image's release
(`/etc/vinix-release`), or of the newest release for an image built without
one. Build an unpublished image to test with
`VINIX_RELEASE= scripts/deploy-iso.sh --tag=test-NAME --no-test --no-publish`,
so that it downloads them from a release that exists.

The serial log, screenshots of each step and one of the Terminal when an app
fails go to `build/first-run-apps/ARCH` (`--out=DIR`). `--keep` leaves the VM
running afterwards; its QMP socket is in that directory. `--apps=A,B` chooses
only those apps (`--apps=` none, which leaves a desktop to experiment on), and
`run DIR key|type|click|shot ...` drives a VM a run left in DIR.
