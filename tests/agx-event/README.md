# AGX event slot reuse

Run `v run tests/agx-event/run.v --sanitize`. The runner executes the production
event manager with host locks, atomics and fence signals. It verifies the reference's
initial slot counter values, persistent firmware counters across 300 slot reuses, stale-completion isolation, an unarmed
new owner, wrap through zero, and exactly-once fence signaling. Set
`AGX_EVENT_TEST_BINARY` to retain the native executable outside the repository.

# Shared workqueue events

The fixture also executes production `WorkQueueEvents` ownership. A batch of
64 tickets consumes one physical slot, earlier values retire independently,
and the last owner releases it. Tests reject out-of-order/double publication,
double release and a 128th outstanding ticket; they cover the bounded sequence
window, cancellation rollback of both stamp and event sequence, and wrap.
The preparation table holds 127 tickets; publication independently preserves
Asahi's spare event using last-published minus host-completed stamp deltas.
One thousand full-window cycles verify 126-event publication, withheld host
acknowledgment despite GPU progress, signed/zero wrap, monotonic reverse cleanup,
tail rollback and cancellation holes. Canceling every earlier reservation still
admits the first actual job; its published gap then holds later jobs until host
retirement. These checks use real event code and injected host locks/atomics.
Initial-event selection also runs 1,000 cancellation/ABA/older-unpublished/
slot-rollover/producer-retirement cycles. Host reservation identities never
roll back with a canceled firmware value or sequence. Wrapped zero-valued
targets remain valid. The selector excludes future reservations and blocks
any unpublished reservation at or before its captured cutoff.
