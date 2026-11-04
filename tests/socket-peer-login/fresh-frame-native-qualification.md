# Fresh frame preparation and native control qualification

Source base: `4e52d3561e267e96735c91b65ddc4057cffb0ed6`. Qualification ran
against the exact source/tool hashes retained in the external receipts.
The subsequent [native kernel build](fresh-frame-native-build.md) and
[complete-state audits](fresh-frame-full-audit.md) passed; guest/performance
validation remains pending.

The fixed V preparer is
`prepare-fresh-frame.v` SHA256
`68620393ddbf4d90defcdc4c6e1393cf8046a17fa9db23d2eabc0bdb73cc9267`.
It prepares fresh detached `b262bf48` sources, copies the four pinned frame
files and two checkers, preserves the three pristine peer socket files, and
changes only the controller's fixed frame worktree binding.

The 220-line V generator `prepare-fresh-frame-observer.v`, SHA256
`d0c206394e78b77924d3acc22f10745f17c6a960cc9572ab8816a26f423b397d`,
derives both external profiles from maintained observer SHA256
`a473233234928cc68a5a6d87e432c2dc34ff5ecb6d5037dfe9bd1cc4e181a006`.
It binds the actual controller source/binary/controls, checks every fixed
replacement and full inverse equality, and retains the complete generated
diffs outside Git. The independent profile changes only seven state literals.

All 12 setup/controller actions, five generator actions and seven native
bootstrap/control actions exited zero. Strict `ff75a301`/clang23 compilation
used `-Werror=incompatible-pointer-types`; each native profile passed all
67 controls. The primary and independent source hashes are respectively
`203100b0be37aae9ba593412da22e30fb7507e5bb6acf7dff7765d974264673c` and
`c5d164a961e4ee2b2784f035658cee22b382e19be091e6291310d049153db73e`.
Their actual binaries are `b9d9e1beb4db7a3f5d7c7d44dc35badef81885ee9cc23b6fda456c990f7fa3f5`
and `30a9b507bd55fbec39fb1d5065d3e87009f0938742a6d5c8ead25ef6b1efdbb3`.

Both closed flood children wrote exactly 2,100,225 bytes and refused on the
specific 2 MiB audit-log bound, with actual ECHILD/ESRCH cleanup. Their child
exits were unobserved; no child exit zero is claimed. Quiet 900 ms refusals and
separate nested-owner cleanup receipts remain preserved. The worker cases
recorded five samples each, maximum gaps 1,010/1,008 ms and sample durations
62/69 ms. All 14 native-phase source/input comparisons and both binary
comparisons returned zero; 13 critical primary fixtures remained unchanged
after the independent suite.

All raw evidence is outside Git under:

`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026-seal-01`

- `setup-actions-01/first-setup-handoff.json`: SHA256 `8383652c665a776ea48ed77e28223bbe5cba6380db6de9d89a5178d158c1d9b4`.
- `native-source-actions-01/phase-A-handoff.json`: SHA256 `d8f741abe4b9274112f6cc1c99de59b8f55f7578d2d6a14be9a56ae7d885313f`.
- `native-control-actions-01/phase-B-handoff.json`: SHA256 `f85f3a2276f7f4b3bba925488d61046fb1693b99d6b1d9614bb209ad29014695`.
- `native-control-actions-01/closed-controls-summary.json`: SHA256 `c837d56667d7d1997905ab888620ea88e9346889b7cefa84d463afcbd79c9fef`.

Setup and bootstrap evidence covers admission/completion endpoints; the
native timing evidence above covers closed controls. The subsequent kernel
build passed native observations within five seconds, the total 1,100-second
entry-through-final-PASS bound and the unchanged inner controller.
Guest/performance validation remains pending. Referenced historical frame/atomic
bundles and preflight documents are unchanged.
