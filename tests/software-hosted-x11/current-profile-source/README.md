# Production-qualified current proof source overlay

These three V files preserve the exact candidate used by the production host
guard and provenance qualification on 2026-11-05. They stay outside the active
`compactproof` package. Their headers, including their original draft wording,
are retained byte-for-byte; this README records the later qualification context.

| Source | SHA-256 |
| --- | --- |
| `current.v` | `69f152fa74e534d7ce0e203d2d01a088159e8b9f8cbc97ea2c227be5acc2dfde` |
| `current_controls.v` | `f5a82076a420255e6ebff067c5c539dccdef800900f84fbd60fcbfa2b3fbc7b8` |
| `currentcheck/main.v` | `2f79a191c7cb551f49bd7ca9b5279ec85447531e53f05cbd8a7355a591e14730` |

The files are an overlay on the independently copied, host-qualified
[`compactproof` template](../compactproof/README.md) from `be6c728ed`. That
template's existing files remain required, including `admit.v` at
`558e3d949d310b54d8550bb8d51bbabfab395655f58afdb6167bf1f42fc58f80`
and `controls.v` at
`8b0ea41834fac2b4959ca30d6f9f2d0b2d90e18973a9fa5b2c190f59fb6b8e61`.
The unchanged dependencies remain required: `proof/admit.v` at
`eca382bae5e5dc3aa8afed0bd2d0453d69648df7b02368da21699ad1e123289e`,
`launchproof/admit.v` at
`e8ba120b8b4ac08207bd53be979c5d6ea8085eb11df4689025b107ab0f1aeb94`
and `optionsfixture/fixture.v` at
`c5d895e978fb42959de5824ea5945683edd3acab05f0fd126cf963d59b369b56`.
These files use private helpers from the template and must be placed beside its unchanged
sources in an independent module copy before compilation. The entry was copied
to the private Suite's fixed `compactproof-check.v` build path for qualification.
No overlay has been installed in the maintained active package.

The exact derivation remains part of the required provenance. The complete
frozen twelve-file source package is retained outside Git beneath
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01/current-profile-draft-01`.
Its `SHA256SUMS` is
`f5d5134d7c4e294aab792da798c389b7c909b519124806f1b7b8628d100ccd69`.
The source preparation used the independently retained preparer source
`afc2878103a458067fbe0eff43be933ce7d26b4c22f0f3e3d8436a7e573e720a`,
recorded by `322bbb927`. It preserved the older module sources, factored the
unchanged record-pair guards into one shared helper and changed only two
early-refusal fixtures to call that helper. Original and candidate sources,
complete diffs and before/after maps remain in the sibling
`current-proof-setup-01` directory. Its result hash is
`34a882a54b23f8fb411503ac9e9bb74a837f77b67f676c7328fdf92f1b70c933`.
The frozen package, original checker, historical refusals and complete evidence
remain required by the fixed profile; preserving these sources changes none of
those checks. Details are in
[the source preparation report](../current-proof-source-preparation.md).

The private candidate passed strict production compilation and all eight
historical plus seven current host control categories. The prepared source map
and all four module maps before/after the build and controls share
`710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4`.
The executable is
`246b4cb824e85b819338f65cce5d7ee5ca68f137bc3900291ceda719444f3f8a`.
The synthetic current record contains 132 fixed input roles and six callback
receipt roles and occupies 36,699 bytes, below the unchanged 64 KiB limit.
The actual build, cleanup, compiler and control receipts are identified in
[the host qualification report](../current-proof-host-qualification.md), committed
as `ef9781456`.

This source capture was verified by byte comparison to the actual private Suite
and its prepared candidate copies. It requires no compiler or control rerun.
The qualified scope covers host readers, provenance, record/token separation
and shared guard refusals with synthetic callbacks. Public assembly, actual
whole-root consumption checks, imports, controller/retainer integration,
evidence refusals and both native Launch options guests remain separate gates.
