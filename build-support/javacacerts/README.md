# Native Java trust-store writer

`../java-cacerts` builds a deterministic JKS v2 trust store from the PEM
certificate blocks in a directory's sorted `*.crt` files. It preserves DER
bytes, duplicate and empty blocks, SHA-256 aliases, zero creation timestamps,
the `X.509` entry type, and the original permissive base64 padding rules.
The JKS checksum uses the password's UTF-16BE code units and SHA-1, as required
by the file format. The default password is `changeit`.

`../java-cacerts-stage.v --arch aarch64|x86_64 --staging DIRECTORY` builds a
static Linux musl executable and installs it as
`usr/libexec/vinix-minecraft/java-cacerts`. Image builders and the package
frontend use this executable directly. Staging validates the compiler target
and ELF architecture, publishes through an exclusive temporary file, and
removes the obsolete Python helper from cached layers.

Run the native contract checks with `v -nocache -cc cc test build-support/javacacerts`.
Set `VINIX_JAVA_CACERTS_TOOL` to a compiled command to include CLI checks.
`VINIX_JAVA_REPO` enables comparison with the cached 119-certificate production
store. Its pre-port SHA-256 is
`a25f4464a74cfba595a04f135b3ee2f6927479161baac152feef2161cc893bad`.
Set `VINIX_JAVA_KEYTOOL` to a host OpenJDK `keytool` to verify both default and
supplementary-Unicode passwords with an independent JKS reader.
