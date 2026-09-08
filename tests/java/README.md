# OpenJDK smoke test

`smoke.sh` runs inside the aarch64 Vinix userland. It verifies the Alpine
OpenJDK JRE and JDK, compiles `VinixJavaSmoke.java` with `javac`, packages the
class with `jar`, and runs it from both a class directory and the resulting
archive. The Java program exercises files, cryptography, threads and TCP
loopback networking.

Build the OpenJDK overlay and userland with:

```sh
./build-java-aarch64.sh
./build-userland-aarch64.sh
```

The ARM64 VM userland boot suite invokes `/root/java-smoke.sh` automatically.
