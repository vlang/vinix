# Native V application packages

Build with `v -o /tmp/vinix-package tools/packages/main.v`. Install/state commands
support a disposable `--root /absolute/root`. Launch requires the real root and an
ordinary user session.

Both desktop builders use the existing native security-tools staging path.
Standalone staging and qualification are also available:

```sh
v run tools/packages/stage.v --arch aarch64 --staging /path/to/root
v run tools/packages/stage.v --arch x86_64 --staging /path/to/root
v run tests/packages/distribution-check.v --cross --desktop
```

Desktop checks need generated examples under `build/app-src` and a headless ui2
overlay under `build/vmodules`; `VINIX_PACKAGE_TEST_UI2` selects another overlay
parent. Package implementation, publishing, staging and qualification use V.

Read [administration/recovery](../../docs/application-distribution.md) and
[SDK 1](SDK.md) for enrollment, policy, packaging and limits. Release publisher
enrollment and catalog/runtime guest qualification remain required.
