# Current target bootstrap source staging

`stage-current-target-bootstrap.v` compiled with strict pointer diagnostics and
staged the ten fixed sources successfully. A second invocation refused the
existing scope; the receipt and every copied file remained byte-identical.
This qualifies source staging, not compiler relocation, input freezing, kernel
builds or guest execution. The repository revision before this change was
`69f960100`.

The stager admits only `--stage` and the fixed output directory. It checks each
reviewed source digest, ordinary-file type, owner, mode and single link before
copying, then verifies independent destination inodes and complete before/after
identities. Access times are excluded because reading may update them. Sources
are the pinned freezer, two already captured guards and seven already captured
sourcecommand files; historical source captures are read-only inputs.

Complete evidence is retained below
`/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01/target-freeze-host-01`.
The `copier-bootstrap-01` subdirectory retains the as-run source, argv, private
cache/modules/temp, generated C, executable, compiler log and actual statuses.
The pinned ff75 host compiler built with `-prod -nocache -keepc`, clang23 and
`-Werror=incompatible-pointer-types`. Actual compile status was 0; the 529-byte
log contains only a local-variable shadow notice. The original complete host
compiler overlay checks passed before and after. Selected direct tool/SDK pins
and all 326 regular resource-header hashes matched before and after.

Actual staging returned 0 and `CURRENT TARGET BOOTSTRAP SOURCE PASS 10`.
Repeat staging returned 1 and the exact fresh-scope refusal. Both hash lists
match, including `source-stage.json` and all ten copies. Retained identities
show mode 0644, UID 501/GID 20, one link and independent destination inodes.
An independent review also checked the source and fixed input bindings.

| Artifact | SHA-256 |
| --- | --- |
| Maintained/as-run stager source | `24b4651b2dff45953b31e13f1f2566a52c0ee7863df7ad3bec6ed63409776fe2` |
| Stager executable | `b9c2e854bb59361e217a0f2e04d02543ca9cce7a3d7d1f37d3f885d1c7bc7ed5` |
| Retained generated C | `9f9407964e58b69c16a433cb668cb6498d30e6120fea7f7fd750c53af12d346b` |
| `source-stage.json` | `ef87682fe63f1bb5e426ad723c2965e8dcf7b4d5d35008391ed9b2c92e24579a` |
| `copier-bootstrap-01/actual-status.json` | `c77314a377469418b5a4fb917836969db50f43051dd21c327d955619c6e983b7` |
| Both repeat-stage hash lists | `71b0014136c9c44ba9f4ffd1568cb95f8fdcbf976835c328b4d73e8b30970a09` |

Initial bootstrap operations used GNU timeout and endpoint accounting. They
make no typed process-group cleanup or continuous allocation/RSS claim. At the
closed staging endpoint, the entire setup occupied 2,240 KiB allocated and
2,158 KiB apparent, inside its 16 MiB allowance within the existing cumulative
512 MiB kernel budget. Later bootstrap, refusal and audit artifacts remain
charged. Freezer compilation and its separately admitted input phase still
require their own results.
