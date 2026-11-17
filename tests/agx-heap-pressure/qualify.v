// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	assert os.args.len == 2
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args[1])
	assert !state.starts_with(repo + '/') && os.real_path(state) == state
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-worker-reschedule-20261117/bundle'
	for item in [['tests/agx-heap-gc/qualify.v', 'qualify'], ['tests/agx-worker/native.v', 'native']] {
		assert hash(repo + '/' + item[0])! == hash(prior + '/source/' + item[0])!
		os.cp(prior + '/' + item[1], state + '/' + item[1])!
	}
	mut p := os.new_process(state + '/qualify'); p.set_args(['--prepare', state]); p.run(); p.wait(); assert p.code == 0; p.close()
	os.cp(repo + '/kernel/gpu/agx/alloc/alloc.v', state + '/kernel-build/kernel/gpu/agx/alloc/alloc.v')!
	os.mkdir_all(state + '/baseline')!
	for name, path in {'alloc': 'kernel/gpu/agx/alloc/alloc.v', 'gpu': 'kernel/gpu/agx/gpu/gpu.v'} {
		mut show := os.new_process('git'); show.set_work_folder(repo); show.set_args(['show', os.read_file(state + '/baseline.txt')!.trim_space() + ':' + path])
		show.set_redirect_stdio_merged(); show.run(); text := show.stdout_slurp(); show.wait(); assert show.code == 0; show.close()
		os.write_file(state + '/baseline/' + name + '.v', text)!
	}
	println('Prepared isolated allocator/manager overlays and checksum-verified two-job native runner.')
}
