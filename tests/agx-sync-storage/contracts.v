// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn run(program string, args []string, log string) ! {
	mut p := os.new_process(program)
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, output)!
	assert code == 0, log
}

fn main() {
	assert os.args.len == 2, 'usage: contracts EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[1])
	root := state + '/contracts-source'
	assert !state.starts_with(repo + '/') && !os.exists(root)
	os.mkdir_all(root)!
	run('git', ['-C', repo, 'archive', '-o', state + '/contracts.tar',
		'f8d2c9d85bb78c34e97b26bdee880c2ca12656ed', 'kernel', 'tools/agx-re'], state + '/contracts-archive.log')!
	run('tar', ['-xf', state + '/contracts.tar', '-C', root], state + '/contracts-extract.log')!
	mut inventory := []string{}
	for path in ['kernel/gpu/agx/file/file.v', 'kernel/gpu/agx/file/modern_submit.v',
		'kernel/gpu/agx/file/pending.v', 'kernel/gpu/agx/submission/modern.v',
		'kernel/gpu/agx/submission/submission.v', 'kernel/gpu/agx/submission/sync_storage.v',
		'tools/agx-re/g13contract/core.v', 'tools/agx-re/g13contract/core_test.v',
		'tools/agx-re/g13contract/timeline.v', 'tools/agx-re/g13contract/timeline_test.v',
		'tools/agx-re/g13contract/logical_queue_test.v'] {
		bytes := os.read_bytes(repo + '/' + path)!
		if path.starts_with('kernel/') {
			assert sha256.sum(bytes) == sha256.sum(os.read_bytes(state + '/kernel-build/' + path)!)
		}
		os.write_file_array(root + '/' + path, bytes)!
		inventory << path + ' sha256 ' + sha256.sum(bytes).hex()
	}
	os.write_file(state + '/contracts-overlays.txt', inventory.join('\n') + '\n')!
	os.setenv('VJOBS', '2', true)
	run(os.getenv_opt('V') or { 'v' }, ['-path', root + '/tools/agx-re|@vlib|@vmodules', 'test',
		root + '/tools/agx-re/g13contract'], state + '/contracts-scoped.log')!
	assert os.read_file(state + '/contracts-scoped.log')!.contains('71 passed, 71 total')
	println('71 source contract files pass against the isolated native baseline plus owned overlays; concurrent event edits excluded.')
}
