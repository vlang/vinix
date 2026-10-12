@[has_globals]
module kprint

struct Lock {
mut:
	held bool
}

fn (mut gate Lock) acquire() {
	assert !gate.held
	gate.held = true
}

fn (mut gate Lock) release() {
	assert gate.held
	gate.held = false
}

__global kprint_lock Lock

fn test_log_survives_wrap_and_snapshots_do_not_change_after_appends() {
	bootlog = BootLog{}
	assert bootlog_snapshot() == ''
	first := 'rtl8169: PHY startup diagnostics\n'
	bootlog.append(first.str, u64(first.len))
	before := bootlog_snapshot()
	assert before == first
	more := []u8{len: bootlog_bytes + 123, init: u8(index % 251)}
	bootlog.append(more.data, u64(more.len))
	assert bootlog.length == bootlog_bytes
	after := bootlog_snapshot()
	assert after.len == bootlog_bytes
	for i, byte in after {
		assert byte == more[i + 123]
	}
	assert before == first
	bootlog.append(first.str, u64(first.len))
	assert bootlog_snapshot().ends_with(first)
}
