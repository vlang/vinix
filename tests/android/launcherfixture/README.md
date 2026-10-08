The independent V host fixture exercises the maintained `run-android` shell
launcher: all nine original checks cover native helper order, immutable APK
identity, arguments with spaces, private environment, trust-property order,
cache reuse, exit propagation, app-data namespaces, stack limits, help and
missing-input failures. The loader is a real native executable which records
its arguments, environment and resource limits, and implements only the
fixture helper responses. It executes no Android application.
An additional native check fills both child output pipes beyond their
capacity and requires complete output collection without blocking either.

Run `build-support/run-v-tool.sh tests/android/launcher-test.v`. The entry
builds both fixture executables with the selected V compiler and retires its
temporary build directory. The 32 MiB stack case reports a skip when the
host's hard limit prevents it, matching the original condition.

Qualification runs the original frozen Python suite and native cases on
actual ARM64 and x86_64 hosts, with sanitizer checks. Whole launch comparisons
retain raw argument/environment/stack/state records. The records expose three
incidental runtime differences: V supplies `VEXE`, while the original Python
interpreter supplies `LC_CTYPE` and macOS `__CF_USER_TEXT_ENCODING`. These are
recorded separately; every launcher-owned environment field is compared.
