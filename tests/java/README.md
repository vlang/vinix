# OpenJDK smoke test

The maintained V [Java SDK stager](../../tools/development/stage-java.v) and
[development guest controller](../development/README.md) provide a separate
ordinary-account reference gate using prepared package inputs:

```
V_C_ERROR_BUG_REPORT_DISABLED=1 v -cc cc run tools/development/stage-java.v \
  aarch64 /path/to/prepared-java-overlay java-25-openjdk /path/to/new-java-stage

V_C_ERROR_BUG_REPORT_DISABLED=1 \
VINIX_DEVELOPMENT_REFERENCE_SDK=/path/to/new-java-stage/sdk \
VINIX_DEVELOPMENT_REFERENCE_PROFILES=java \
VINIX_DEVELOPMENT_REFERENCE_JIT=1 \
tests/development/run-guest aarch64 /path/to/kernel /path/to/staged-tools /path/to/new-state
```

The explicit JIT option grants only the administrator-owned JDK a read-only
`nosuid,nodev,wxallowed` executable mount in the disposable guest. Requests
before approval, outside that mount and after revocation must fail; UID 1000
cannot remount or write the installation. The Java project records the actual
child environment, versions and executable pins, compiles, builds a JAR with
fixed entry timestamps, and executes its thread/file checks in two private
workspaces. Class, JAR and readback artifacts must match. The qualifier does
not grant production mount approval; the standalone CLI requires the system
administrator to prepare that policy separately.

`smoke.sh` runs inside the aarch64 Vinix userland. It verifies the Alpine
OpenJDK JRE and JDK, compiles `VinixJavaSmoke.java` with `javac`, packages the
class with `jar`, and runs it from both a class directory and the resulting
archive. The Java program exercises files, cryptography, threads and TCP
loopback networking.

Build the OpenJDK overlay and userland with:

```sh
./scripts/build-java-aarch64.sh
./scripts/build-userland-aarch64.sh
```

The ARM64 VM userland boot suite invokes `/root/java-smoke.sh` automatically.
