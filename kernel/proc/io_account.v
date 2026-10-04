// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module proc

import katomic
import lib

__global (
	machine_disk_read_bytes u64
	machine_disk_write_bytes u64
	machine_net_recv_bytes u64
	machine_net_send_bytes u64
)

// Count only successful bytes, at completion. Drivers call the physical-disk
// path; file handles call the logical-file path. The distinction matters for
// cached reads and memory files, which perform no physical storage I/O.
pub fn account_file_transfer(bytes i64, write bool) {
	if bytes <= 0 { return }
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } { return }
	if write { add_cpu_counter(&t.process.io_write_bytes, u64(bytes)) }
	else { add_cpu_counter(&t.process.io_read_bytes, u64(bytes)) }
}

pub fn account_disk_transfer(bytes u64, write bool) {
	if bytes == 0 { return }
	if write { add_cpu_counter(&machine_disk_write_bytes, bytes) }
	else { add_cpu_counter(&machine_disk_read_bytes, bytes) }
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } { return }
	if write { add_cpu_counter(&t.process.disk_write_bytes, bytes) }
	else { add_cpu_counter(&t.process.disk_read_bytes, bytes) }
}

// ANS also serves its native filesystems through C, bypassing V block
// resources. Its low-level command completion uses the same physical counter.
@[export: 'vinix_account_disk_transfer']
fn account_disk_completion(bytes u64, write int) {
	account_disk_transfer(bytes, write != 0)
}

// These are IPv4/IPv6 socket payload bytes, including loopback. Unix sockets
// and retransmitted protocol headers are deliberately excluded.
pub fn account_network_transfer(bytes i64, send bool) {
	if bytes <= 0 { return }
	if send { add_cpu_counter(&machine_net_send_bytes, u64(bytes)) }
	else { add_cpu_counter(&machine_net_recv_bytes, u64(bytes)) }
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } { return }
	if send { add_cpu_counter(&t.process.net_send_bytes, u64(bytes)) }
	else { add_cpu_counter(&t.process.net_recv_bytes, u64(bytes)) }
}

pub fn machine_io_text() string {
	mut text := lib.new_text(192)
	text.add('disk_read_bytes: ')
	text.add_unsigned(katomic.load(&machine_disk_read_bytes))
	text.add('\ndisk_write_bytes: ')
	text.add_unsigned(katomic.load(&machine_disk_write_bytes))
	text.add('\nnet_recv_bytes: ')
	text.add_unsigned(katomic.load(&machine_net_recv_bytes))
	text.add('\nnet_send_bytes: ')
	text.add_unsigned(katomic.load(&machine_net_send_bytes))
	text.add('\n')
	return lib.finish_text(text)
}

pub fn process_io_text(pid int) string {
	lock_table()
	defer { unlock_table() }
	p := process_at(pid)
	if p == unsafe { nil } { return '' }
	mut text := lib.new_text(256)
	text.add('rchar: ')
	text.add_unsigned(katomic.load(&p.io_read_bytes))
	text.add('\nwchar: ')
	text.add_unsigned(katomic.load(&p.io_write_bytes))
	text.add('\nread_bytes: ')
	text.add_unsigned(katomic.load(&p.disk_read_bytes))
	text.add('\nwrite_bytes: ')
	text.add_unsigned(katomic.load(&p.disk_write_bytes))
	text.add('\nnet_recv_bytes: ')
	text.add_unsigned(katomic.load(&p.net_recv_bytes))
	text.add('\nnet_send_bytes: ')
	text.add_unsigned(katomic.load(&p.net_send_bytes))
	text.add('\n')
	return lib.finish_text(text)
}
