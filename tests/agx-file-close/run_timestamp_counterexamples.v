// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
	assert os.args.len == 3, 'usage: run_timestamp_counterexamples CLOSE_RUNNER FRESH_EXTERNAL_DIRECTORY'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	mut receipts := []string{}
	for name, spec in {
		'null-handle-offset': ['timestamp', 'if timestamp.handle == 0', 'if timestamp.handle == 0 && timestamp.offset == 0', 'file.check_timestamp_captures:', 'timestamp lookup/overflow/range precedence'],
		'missing-name-error': ['timestamp', 'return -2, G13TimestampCapture{}', 'return -22, G13TimestampCapture{}', 'file.check_timestamp_captures:', 'timestamp lookup/overflow/range precedence'],
		'overflow-error': ['timestamp', 'if timestamp.offset > ~u32(0) - u32(8) { return -22,', 'if timestamp.offset > ~u32(0) - u32(8) { return -34,', 'file.check_timestamp_captures:', 'timestamp lookup/overflow/range precedence'],
		'address-offset': ['timestamp', 'address: object.va + u64(timestamp.offset)', 'address: object.va', 'file.check_timestamp_captures:', 'timestamp byte address'],
		'missing-reference': ['timestamp', 'object.references++', 'object.references += 0', 'file.check_timestamp_captures:', 'references == 1'],
		'accept-detached': ['timestamp', ' || object.detached', '', 'file.check_timestamp_captures:', 'captured timestamp survives namespace removal'],
		'missing-rollback': ['timestamp', 'f.release_g13_timestamps(mut references); return code', 'return code', 'file.check_timestamp_captures:', 'partial capture rollback'],
		'missing-release': ['timestamp', 'f.timestamp_objects[index].references--', 'f.timestamp_objects[index].references += 0', 'file.check_timestamp_captures:', 'references == 0'],
		'early-reap': ['timestamp', 'if !object.detached || object.references != 0 { continue }', 'if !object.detached { continue }', 'file.check_timestamp_captures:', 'worker cannot reap a captured timestamp'],
		'unbind-drops-capture': ['file', 'if found.references != 0 {', 'if false && found.references != 0 {', 'file.check_timestamp_captures:', 'UNBIND must retain captured mapping'],
		'close-drops-capture': ['file', 'if object.references != 0 { f.lock.release(); return false }', 'if false && object.references != 0 { f.lock.release(); return false }', 'file.check_timestamp_captures:', 'capture pins file before VM pin'],
		'close-drops-missing-manager': ['file', 'if manager == unsafe { nil } && f.timestamp_objects.len != 0 {', 'if false && manager == unsafe { nil } && f.timestamp_objects.len != 0 {', 'file.check_timestamp_captures:', 'close cannot drop mapped backing without manager'],
		'missing-worker-retry': ['file', 'owned.reap_detached_timestamp_objects_locked()', '', 'file.check_timestamp_captures:', 'worker retries detached timestamp cleanup'],
		'map-without-lock': ['gpu-map', 'mgr.lock.acquire()\n\tdefer { mgr.lock.release() }', '', 'gpu.agx.gpu.TimestampAllocator.alloc:', 'timestamp_lock_held()'],
		'unmap-without-lock': ['gpu-unmap', 'mgr.lock.acquire()\n\tdefer { mgr.lock.release() }', '', 'mmu.UatManager.unmap_kernel:', 'timestamp_lock_held()']
	} {
		path := match spec[0] { 'timestamp' { 'kernel/gpu/agx/file/timestamps.v' } 'file' { 'kernel/gpu/agx/file/file.v' } else { 'kernel/gpu/agx/gpu/gpu.v' } }
		source := os.read_file(repo + '/' + path)!
		mut begin := 0; mut end := source.len
		if spec[0].starts_with('gpu-') {
			marker := if spec[0] == 'gpu-map' { 'pub fn (mut mgr GpuManager) map_g13_timestamp_buffer(' } else { 'pub fn (mut mgr GpuManager) unmap_g13_timestamp_buffer(' }
			begin = source.index(marker) or { panic(marker) }
			end = source.index_after('\n}\n', begin) or { panic('method end') }
		}
		body := source[begin..end]
		assert body.count(spec[1]) == 1, name
		mutant := source[..begin] + body.replace(spec[1], spec[2]) + source[end..]
		directory := state + '/' + name
		os.mkdir_all(directory)!
		os.write_file(directory + '/source.v', mutant)!
		os.setenv('AGX_CLOSE_TEST_BINARY', directory + '/test', true); os.unsetenv('AGX_CLOSE_TEST_C')
		mut process := os.new_process(os.abs_path(os.args[1]))
		option := match spec[0] { 'timestamp' { '--timestamp-source' } 'file' { '--file-source' } else { '--gpu-source' } }
		process.set_args([option, directory + '/source.v']); process.set_redirect_stdio(); process.run()
		log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
		os.write_file(directory + '/run.log', log)!
		assert process.code != 0 && log.contains('FAIL: fn ' + spec[3]) && log.contains(spec[4]) && !log.contains('error:'), name + ': ' + log
		assert os.is_file(directory + '/test'), name + ' must compile before failing'
		process.close()
		receipts << name + ' sha256 ' + sha256.sum(mutant.bytes()).hex()
		println(name + ': compiled; designated timestamp ownership/locking assertion failed')
	}
	os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
