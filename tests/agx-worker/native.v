// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn run(program string, args []string, folder string, log string, expected int) ! {
	mut p := os.new_process(program); p.set_args(args); p.set_work_folder(folder)
	p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	os.write_file(log, out)!
	assert code == expected, log
}
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	assert os.args.len == 3, 'usage: native aarch64|x86_64|allocations STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2]); assert !state.starts_with(repo + '/')
	work := state + '/kernel-build'
	os.setenv('VTMP', state + '/tmp', true); os.setenv('VJOBS', '2', true)
	if os.args[1] == 'allocations' {
		os.setenv('VINIX_KERNEL_ALLOCS_ROOT', work, true)
		run(repo + '/tests/kernel-allocs/run.sh', [], repo, state + '/kernel-allocs.log', 1)!
		return
	}
	arch := os.args[1]; assert arch in ['aarch64', 'x86_64']
	assert !os.exists(state + '/vinix-' + arch)
	run('make', ['clean', 'ARCH=' + arch], work + '/kernel', state + '/clean-' + arch + '.log', 0)!
	run('make', ['-j2', 'ARCH=' + arch, 'LD_X86_64=ld.lld', 'KERNEL_LINK_SEED=0'], work + '/kernel', state + '/build-' + arch + '.log', 0)!
	for path in os.walk_ext(repo + '/kernel/gpu/agx', '.v') {
		rel := path[repo.len + 1..]; assert hash(path)! == hash(work + '/' + rel)!, rel
	}
	for file in ['bin/vinix', 'obj/blob.c'] {
		name := if file == 'bin/vinix' { 'vinix-' + arch } else { 'blob-' + arch + '.c' }
		os.cp(work + '/kernel/' + file, state + '/' + name)!
		println(name + ' sha256 ' + hash(state + '/' + name)!)
	}
	mut inventory := []string{}
	for path in os.walk_ext(work + '/kernel', '.v') {
		if path.contains('/obj/') || path.contains('/.cache/') { continue }
		inventory << path[(work + '/').len..] + ' sha256 ' + hash(path)!
	}
	inventory.sort(); os.write_file(state + '/inputs-' + arch + '.txt', inventory.join('\n') + '\n')!
}
