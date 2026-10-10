// SPDX-License-Identifier: GPL-2.0-or-later
module ans

import apple.ans.anscore
import errno
import resource

fn (mut dev AnsBlock) block_status() resource.BlockStatus {
	ans_lock.acquire()
	defer { ans_lock.release() }
	state := anscore.namespace_status(dev.ns_index)
	if !state.valid || state.metrics.disk_id == 0 { return resource.BlockStatus{
			version: 0
		} }
	mut flags := resource.block_flush
	if !ans_ready || state.offline { flags |= resource.block_offline }
	if !ans_ready || state.offline || dev.partition < 0 || dev.partition != state.writable_partition {
		flags |= resource.block_readonly
	}
	if dev.partition >= 0 { flags |= resource.block_parent_counters }
	return resource.BlockStatus{
		bytes:       u64(dev.stat.size)
		sector:      u64(dev.stat.blksize)
		flags:       flags
		reads:       state.metrics.reads
		writes:      state.metrics.writes
		read_bytes:  state.metrics.read_bytes
		write_bytes: state.metrics.write_bytes
		flushes:     state.metrics.flushes
		errors:      state.metrics.errors
		last_error:  state.metrics.last_error
		disk_id:     state.metrics.disk_id
		start:       dev.offset
	}
}

fn (dev &AnsBlock) record_failed() {
	failure_code := errno.get()
	ans_lock.acquire()
	anscore.namespace_failed(dev.ns_index, failure_code)
	ans_lock.release()
}
