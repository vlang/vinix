# Independent ext2 and NBD fixture

`export_query.v` and this module execute the original fixture bodies in V.
`export-test.py` retains all six unittest IDs, public signatures, imports,
entrypoint and its local negotiation-handler callback. The callback's class
construction, closure and three statements receive no port credit. Assertions
still call the actual caller's `unittest.TestCase` methods; stdlib sockets,
threads, paths, subprocesses and e2fsprogs/QEMU clients remain actual objects.

The fixture uses the production exporter's generic borrowed-object transport
with a separate `VINIX_EXT2_FIXTURE_QUERY` controller. It contains independent
test policy and calls the public exporter API. Its query does not invoke the
production builder's dispatch for fixture operations. Added generic assertion,
name-resolution and active-error library-call bindings receive zero algorithm
credit. Every adapter and remaining Python byte stays counted by Linguist.

Context managers are retained separately from their entered values, and are
removed from the owner table before exit. Normal exit results are not coerced
to bool. Saved errors remain active during client close, server shutdown and
thread join, preserving cleanup order, exception identity, suppression and
exception precedence. Deliberate traceback property changes are retained.
The original cleanup boundary begins after thread startup and client creation;
their pre-existing failure ownership is unchanged. Query processes retire
before fallback managers. Query children have their own process group and
ignore SIGINT so caller cleanup can finish.

Frozen source is `da3885cafa750831a11db8ada48aa81e14d7e5c1`. The final
ARM64, actual Rosetta x86_64 and ARM ASan/UBSan comparisons each passed all
six real original/native cases, including actual e2fsck, debugfs and qemu-io
NBD boundary reads. Five cases compare complete caller assertion plans; a
separate positive sparse-stat library control also compares the complete
sixth plan and executes its real commands. Only private temporary roots and
debugfs inode timestamps are normalized. Each profile also passed 73 owner,
startup and client protocol/scalar controls and 100 requests with exact file
descriptor equality and no remaining children. Both ABIs passed unchanged
API/AST checks, three CLI pairs without a compiler and actual cold compilation
and all six cases. Production requalification retained its 480 ARM pairs and
17 ownership/retirement controls plus 100 requests on every profile.

Earlier real APFS runs failed the original metadata or package sparse-storage
bound. The final runs passed those same bounds after allocation reuse; no
limit, deadline, test ID or assertion changed. The qualification records each
real result and identifies the additional positive library control explicitly.
An initial comparison harness incorrectly required APFS to fail; its failure
and the later correction are retained. An initial CLI harness used a different
script basename and changed argparse wrapping; it was corrected to the same
basename while preserving CLI assertions.

Local frozen sources, original AST scope, profile binaries, raw attempts,
qualification and post-commit receipts are in
`~/.cache/vinix-python-to-v/dota-ext2-fixture-20261009/`. Gross scope is 8,563
original AST body bytes/147 lines. No exact traceback frame-list parity,
new C implementation, kernel build, desktop guest or device result is claimed.
