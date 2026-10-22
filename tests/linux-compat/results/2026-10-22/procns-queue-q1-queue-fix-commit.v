import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/queue-fix'
const commit = 'ec5631d664a8148c063b1ef9ac3f9657a3a0386a'

fn run(args []string, folder string, label string) !string {
	mut process := os.new_process('git')
	process.set_args(args)
	process.set_work_folder(folder)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	os.write_file(area + '/' + label + '.log', output)!
	os.write_file(area + '/' + label + '.status', '${code}\n')!
	assert code == 0, output
	return output
}

fn main() {
	arm := area + '/kernel-arm'
	before := sha256.sum(os.read_bytes(arm + '/kernel/fs/removed.v')!).hex()
	assert os.read_file(arm + '/kernel/fs/removed.v')! == os.read_file(area + '/removed-after-arm.v')!
	assert run(['diff', '--name-only'], arm, 'pre-adopt-arm')!.trim_space() == 'kernel/fs/removed.v'
	run(['reset', '--mixed', commit], arm, 'adopt-arm')!
	assert sha256.sum(os.read_bytes(arm + '/kernel/fs/removed.v')!).hex() == before
	for suffix in ['x86', 'arm'] {
		tree := area + '/kernel-' + suffix
		assert run(['rev-parse', 'HEAD'], tree, 'head-' + suffix)!.trim_space() == commit
		assert run(['status', '--porcelain', '--untracked-files=no'], tree, 'clean-' + suffix)!.trim_space() == ''
		assert run(['diff', commit + '^', commit, '--', 'kernel/fs/removed.v'], tree, 'committed-' + suffix)! == os.read_file(area + '/source-' + suffix + '.diff')!
	}
	os.write_file(area + '/queue-commit.txt', commit + '\n')!
	println('Committed one-file candidate and adopted identical clean tracked trees: ' + commit)
}
