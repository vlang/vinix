// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	assert os.args.len == 2
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args[1])
	assert !state.starts_with(repo + '/') && os.real_path(state) == state
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-heap-cancel-20261117/bundle'
	assert hash(repo + '/tests/agx-heap-pressure/qualify.v')! == hash(prior + '/source/tests/agx-heap-pressure/qualify.v')!
	os.cp(prior + '/prepare', state + '/base-prepare')!
	mut p := os.new_process(state + '/base-prepare'); p.set_args([state]); p.run(); p.wait(); assert p.code == 0; p.close()
	os.cp(repo + '/kernel/gpu/agx/gpu/g13.v', state + '/kernel-build/kernel/gpu/agx/gpu/g13.v')!
	mut show := os.new_process('git'); show.set_work_folder(repo)
	show.set_args(['show', os.read_file(state + '/baseline.txt')!.trim_space() + ':kernel/gpu/agx/gpu/g13.v']); show.set_redirect_stdio_merged(); show.run()
	text := show.stdout_slurp(); show.wait(); assert show.code == 0; show.close(); os.write_file(state + '/baseline/g13.v', text)!
	println('Prepared isolated G13 teardown overlay and checksum-verified two-job native runner.')
}
