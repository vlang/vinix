# Audio continuation draft review checkpoint

2026-11-05: source review only. The parallel format-2 implementation has not
been compiled, tested, integrated or qualified. No donor/source manifest,
continuation preparation, original audit or guest was created by this draft.
The existing format-1 producer and historical evidence remain unchanged.

The draft is retained outside the main checkout at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-aarch64-prepare-20261104-01/audio-continuation-source-01`.
Its detached base is `156c7497640dbf2015fae375ae12dccf64683956`; tracked diff
is empty, with the proposed files untracked. Its plan is
`tests/packages/audio-portal-continuation-plan.md`. The adjacent external
`audio-continuation-draft-review-01.sha256` records all thirteen draft source,
test and plan files. Its SHA256 is
`b5982fa9c98765e1ff777ba18ff4e6f0eaab769ad0819a396222154d12282a3f`;
all thirteen listed checksums were independently reread and matched. This
checkpoint does not commit unvalidated implementation.

The draft separates immutable failed captures/content store from fresh target
outputs. Review found the fixed donor roles, canonical containment, complete
inventory comparison and hard-link closure sound in principle. Its budget
refuses the current retained headroom before creating a preparation state.
These source findings do not establish executable behavior.

Acceptance blockers remain:

- Frozen command receipts admit an executable allowlist without checking each
  role's exact argv, source, flags, output paths and environment. Bind complete
  command specifications in both producer and verifier.
- Final receipt publication precedes fallible validation/deadline/cap gates.
  A later failure plus failed refusal writing can leave a verifiable completed
  receipt. Completion must remain absent through failure-capable gates.
- ELF admission omits execute permission; require it for all eight targets.
- Detached HEAD identity alone does not prove clean committed contents. Either
  validate committed content or explicitly model reviewed content plus base
  provenance, without promising dirty-tree refusal.
- Failure observation stops at the first donor-root error and substitutes an
  empty forest. Preserve independently obtainable capture/store observations
  and errors without relaxing strict acceptance.
- The native `open` mode argument uses V-int variadic metadata. Use the native
  promoted 32-bit type and inspect generated C when compilation is admitted.

The draft contains 21 unexecuted pure tests: eight budget, six inventory and
seven trace cases. Full schema, owner-failure and frozen-receipt regressions
remain required, including these review findings. There is no host acceptance.

A proposed initial host-validation phase may consume at most 96 MiB of new
cumulative growth, including source/closure copies, caches, normal/production
generated C and binaries, fixtures, logs and every failure; 16 MiB stays reserved
inside that ceiling. It must also fit the unchanged 2 GiB aggregate audio cap
and pass fresh 2 GiB free-space admission with a 1 GiB live floor. This scope
does not authorize real manifests, preparation, audits or guests. Source fixes,
independent review and a concrete rounded projection/argv/closure plan must
precede any such validation. Repeated shared-disk admission failures currently
block execution; all draft findings above remain unresolved.
