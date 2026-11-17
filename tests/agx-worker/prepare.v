// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	assert os.args.len == 2
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[1]); assert !state.starts_with(repo + '/')
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-uat-poll-20261117/bundle'
	assert hash(repo + '/tests/agx-heap-gc/qualify.v')! == hash(prior + '/source/tests/agx-heap-gc/qualify.v')!
	os.cp(prior + '/qualify', state + '/qualify')!
	mut process := os.new_process(state + '/qualify')
	process.set_args(['--prepare', state]); process.run(); process.wait(); assert process.code == 0
	for path in ['kernel/gpu/agx/gpu/g17.v', 'kernel/gpu/agx/fake/driver.v'] { os.cp(repo + '/' + path, state + '/kernel-build/' + path)! }
	os.mkdir_all(state + '/baseline')!
	for name, path in {'gpu': 'kernel/gpu/agx/gpu/gpu.v', 'g17': 'kernel/gpu/agx/gpu/g17.v', 'fake': 'kernel/gpu/agx/fake/driver.v'} {
		mut p := os.new_process('git'); p.set_work_folder(repo)
		p.set_args(['show', os.read_file(state + '/baseline.txt')!.trim_space() + ':' + path]); p.set_redirect_stdio_merged(); p.run()
		text := p.stdout_slurp(); p.wait(); assert p.code == 0; p.close()
		os.write_file(state + '/baseline/' + name + '.v', text)!
	}
	println('Prepared three worker overlays, original sources and checksum-verified native runner.')
}
