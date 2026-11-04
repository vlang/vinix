# Global String writer signed fixture host checks

`globalsettingsstringfixture/main.v` generates a signed three-class regression
for the actual public static Global.putString API. Each suite makes fifteen
recorded virtual inserts: twelve boolean outcomes and three exception-identity
checks. Cases cover nullable/empty/Unicode and noninterned String arguments,
exact Global.CONTENT_URI identity, one call, fresh ContentValues, exactly two
explicit keys, arbitrary nonnull/null provider URI and SQLException. Security,
null-pointer and argument exceptions propagate by identity. A separate null
resolver probe requires NPE.

The fixture runs two UI suites and one plain daemon-worker suite with separate
recording resolvers, verifies the actual UI Looper and absent worker Looper,
and uses 8-second join/1-second cleanup while preserving the primary failure.
It requires the actual aarch64/64-bit process. It supplies no SettingsProvider,
permission grant, persistence, getter or Google/Maps success behavior.

Host production passed against source SHA-256
`d162ee8035ba3e3e47660349c2c20b1919540265761d84ba7db8bebf02c1bde9`,
with build revision `31567cabf52b11f4bcd0b2f73c722db54ec2d637`.
Using `S=/Users/alex/.local/state/vinix/android`, complete output is at
`S/global-settings-string-fixture-2026-11-05-r1`:

| Artifact | SHA-256 |
| --- | --- |
| `probe.apk` | `faee136b4cdb500ff165b7b7aceb6649f8af27054593a5905a64f217553c806a` |
| `build.json` | `8b8eb8a9acb58d441e372b5665af04a6a4c5afab3d0e666a2ec2eacbbb2bbbc2` |

Fresh API-28 assembly, disassembly, reassembly and second disassembly passed
with exactly Main/SettingsResolver/Worker and stable canonical sources.
Signature verification requires v3 and exactly one signer; extracted signed
DEX equals the generated DEX. Manifest/package/launcher, source/tool membership
and before/after input hashes passed. All source snapshots, signing material,
tool identities, generated sources and command results remain outside Git.

Frozen builder source/executable and compiler input listing are at
`S/global-settings-string-fixture-build-2026-11-05-r1`; matching controls are
`S/global-settings-string-fixture-controls-2026-11-05-r1`. Compile/build passed
0/0 with empty reasons and complete cleanup: 3,124/8,083 ms, sampled RSS
303,431,680/103,317,504 bytes and shared growth73,728/32,141,312 bytes.
Both retained 600 MiB RSS, 300 seconds, 512 MiB growth, 1 GiB reserve, 4 MiB
output and an 8 GiB shell file cap. Preserve complete bundles and original
tools; aggregate sealing/readback is separate. ARM execution, delivery and
successor GMS/Maps behavior remain pending.
