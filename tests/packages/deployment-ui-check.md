# Software deployment review

Software provides a Deployment form for format-1 root manifests and format-2
deployment locks. It calls `deployment-review FILE`, retains the complete closure
snapshot, and confirms with `--progress deployment-apply FINGERPRINT FILE`. The
literal path is frozen independently of the editable form; it never substitutes
document roots into the generic `apply deploy` command.

Run the maintained V driver with a staged headless ui2 module and generated
desktop assets, using the same environment as the full distribution suite:

```sh
v -o /tmp/distribution-check tests/packages/distribution-check.v
/tmp/distribution-check --direct-tests --software-only --desktop
```

`VINIX_PACKAGE_TEST_UI2` names the parent of the staged `ui2` module;
`VINIX_PACKAGE_TEST_DESKTOP` names generated desktop assets. `V` selects the
compiler and `VINIX_UI2_SOURCE` selects ui2 sources for the launcher heap fixture.
Set `CPATH` to the repository's `desktop` directory for the native fixture's GPU
ABI headers; `VINIX_PACKAGE_TEST_WORK` can select a private temporary parent.
`--software-only` skips unchanged core/protocol/CLI runners; omitting it runs
those checks as well. All runners remain V implementations.

The Software fixture checks asynchronous read-only review, complete dependency
permissions and proprietary licenses, frozen literal argv with spaces and shell
metacharacters, Unicode paths, refusal of invalid/control/oversized pastes,
pending-confirm protection, empty-set removals, cancellation, malformed responses,
stale apply diagnostics, successful catalog return and the mutation close guard.
The heap fixture measures 100 form redraws, 100 review redraws and 100 review/cancel
cycles, including snapshot and frozen-path retirement. The driver also typechecks
the current desktop for both Linux targets and runs existing launcher checks.

The [2026-10-13 receipt](results/2026-10-13/deployment-ui.json) records pinned V
`826e96f`, source and log hashes, commands and qualification limits; the
[retained output](results/2026-10-13/deployment-ui.txt) contains the passing
fixture markers. Both redraw paths retained zero allocations; review/cancel
retirement matched the JSON decoder's independent allocation baseline.
These are host headless UI checks and target typechecks. Deployment service and
offline/runtime mechanics use the earlier [guest qualification](linux-runtime-check.md);
ordinary-user graphical sessions and broader runtime coverage remain release gates.
