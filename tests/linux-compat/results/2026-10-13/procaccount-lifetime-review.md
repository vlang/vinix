Independent selected task-account lifetime review: PASS

Reviewed read-only by the independent `procstat_lifetime_review` agent: final
source, both candidate kernel C files, both actual guest fixture C files and
completed procself raw logs. No lifetime, ownership, descriptor cleanup or
lock-order defect found. No edits or commits made by the reviewer.

The process path takes `pid_lock` then `threads_lock` then `cpu_lock`; the task
path takes `pid_lock` then `cpu_lock`, matching existing readers. CPU charging
releases `cpu_lock` before signal/list/table operations. Selected thread/process
pointers remain valid under the table lock; snapshots return scalars. Text
ownership is unchanged and no pointer escapes or allocation/free path changes.

Fixture rusage and clock outputs remain on stack. Mapped memory is touched and
unmapped before later checks and clock failures. Each opened stat descriptor
closes on new getrusage failures too. Worker storage survives joins; join errors
exit. Actual guest C equals both final previews byte for byte.

Both architectures report six 270-case cohorts with zero failures, successful
stat controls, exactly 256/32/64 demand faults, distinct worker/process fault
and CPU totals, successful namespace checks and flat live slabs across 200
cycles. Large pages remain 63/63 ARM and 160/160 x86. No failure diagnostic or
panic appears. This qualifies lifetime handling for these scalar snapshots;
other accounting/teardown cases remain separate.

| Artifact | SHA-256 |
| --- | --- |
| `kernel/proc/proc.v` | `13380bbfc4265d2a586945d3f076b442769000ee4b6ef1a816cfdad8705bfad3` |
| `tests/linux-compat/procselffixture/core.v` | `30c9d0261b2da42c42c3973ce122d6cec499e07f56abc7554e95c8b5b6a6eed5` |
| Both final previews and actual guest fixture C | `d89821acf4dd209dd09af1673c2e0fe61263c1384ad2191c7b97c0ea73a36fb1` |
| ARM candidate kernel C | `63c99c173dd9dcfcac60ed0d0cfa2124d7d058ed75f991622b9bbf07023e90d5` |
| x86 candidate kernel C | `ca61922747932114bd5574e55f6da460e293e469df3fc7c5c40816bcc4bec25f` |
| ARM final procself serial log | `7266d0db34cea1a868a7b55c212c08b1ad0e7e0c9fd31801684cad9af812420d` |
| x86 final procself serial log | `4be601a8468c3fa60cda3d83e06d77d6bc3a6b8f058c6835c38e1cbd5a5e1b59` |
