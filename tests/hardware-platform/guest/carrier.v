// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn scenario_net_carrier(mut t Test) {
	log := read_text('/proc/bootlog') or { t.check(false, 'carrier selftest boot log unavailable'); return }
	t.check(log.contains('NET-CARRIER PASS:'), 'production DHCP/carrier boot selftest ran')
	before := read_text('/proc/net/dev') or { t.check(false, '/proc/net/dev unavailable'); return }
	t.check(net_dev_row(before, 'lo').len == 16, 'loopback listed with Linux counter layout')
	t.check(net_dev_row(before, 'eth0').len == 16, 'attached interface listed with Linux counter layout')
	t.check(network_works(30), 'restored interface completes DHCP and exchanges packets')
	after := read_net_dev_short() or { t.check(false, 'short reads of /proc/net/dev failed'); return }
	fields := net_dev_row(after, 'eth0')
	if t.check(fields.len == 16, 'short reads keep one coherent interface snapshot') {
		t.check(fields[0].u64() > 0 && fields[1].u64() > 0, 'received bytes and packets counted')
		t.check(fields[8].u64() > 0 && fields[9].u64() > 0, 'transmitted bytes and packets counted')
	}
	// Repeated opens must release their generated procfs snapshots on close.
	_ = drain_net_dev(5)
	initial := heap_usage() or { t.check(false, 'initial heap usage unavailable'); return }
	t.check(drain_net_dev(200), 'repeated interface snapshot reads complete')
	final := heap_usage() or { t.check(false, 'final heap usage unavailable'); return }
	t.check(final.objects - initial.objects <= heap_noise_objects
		&& final.large_pages <= initial.large_pages, 'interface snapshot reads retain no growing allocation')
}

fn drain_net_dev(rounds int) bool {
	mut chunk := [256]u8{}
	for _ in 0 .. rounds {
		fd := C.open(c'/proc/net/dev', C.O_RDONLY)
		if fd < 0 { return false }
		mut result := isize(1)
		for result > 0 { result = C.read(fd, unsafe { &chunk[0] }, 256) }
		C.close(fd)
		if result < 0 { return false }
	}
	return true
}

fn net_dev_row(text string, name string) []string {
	for line in text.split_into_lines() {
		if line.all_before(':').trim_space() == name { return line.all_after(':').fields() }
	}
	return []string{}
}

fn read_net_dev_short() !string {
	fd := C.open(c'/proc/net/dev', C.O_RDONLY)
	if fd < 0 { return error('open failed') }
	defer { C.close(fd) }
	mut bytes := []u8{}
	mut chunk := [7]u8{}
	for {
		count := C.read(fd, unsafe { &chunk[0] }, 7)
		if count < 0 { return error('read failed') }
		if count == 0 { break }
		for i in 0 .. int(count) { bytes << chunk[i] }
	}
	return bytes.bytestr()
}
