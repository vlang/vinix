// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

const prior = '/Users/alex/.local/state/vinix/omarchy-m1-release-policy-20261117'
const reports = ['docs/m1-agx-parity.md', 'docs/m1-agx-heap-gc.md']

fn run(program string, args []string, folder string) !string {
	mut p := os.new_process(program); p.set_args(args); p.set_work_folder(folder)
	p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 0 { return error(program + ': ' + out) }
	return out
}
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn copy_file(source string, target string) ! {
	os.mkdir_all(os.dir(target))!
	if os.exists(target) { assert digest(source)! == digest(target)!, target; return }
	os.cp(source, target)!
}
fn feature_paths(repo string) ![]string {
	mut paths := ['kernel/gpu/agx/fw/channels.v', 'kernel/gpu/agx/gpu/gpu.v', 'kernel/gpu/agx/gpu/g13_garbage.v',
		'tools/agx-re/g13contract/core.v', 'tools/agx-re/g13contract/heap_gc.v', 'tools/agx-re/g13contract/heap_gc_test.v']
	for file in os.walk_ext(repo + '/tests/agx-heap-gc', '.v') { paths << file[repo.len + 1..] }
	paths << 'tests/agx-heap-gc/README.md'
	paths.sort(); return paths
}
fn check_logs(state string) ! {
	assert os.read_file(state + '/test.log')!.contains('528 real heap/channel barrier cases pass')
	assert os.read_file(state + '/unit-final.log')!.contains('65 passed, 65 total')
	assert os.read_file(state + '/negative-wire.log')!.count('compiled; barrier/threshold/ownership assertion rejected') == 10
	assert os.read_file(state + '/check-selftest.log')!.contains('five token/count/allocation/threshold/scheduler mutations rejected')
	assert os.read_file(state + '/check-native.log')!.contains('exact allocation-entry transformation verified')
	assert os.read_file(state + '/check-x86-current.log')!.contains('x86 generated C matches baseline')
	assert os.read_file(state + '/g13.log')!.contains('G13 failure handling: PASS')
	assert os.read_file(state + '/reference.log')!.contains('TVB binding on slot acquisition or heap growth')
	assert os.read_file(state + '/audit.log')!.contains('not_equivalent')
	for arch, total in {'aarch64:': '379', 'x86_64:': '289'} {
		assert os.read_file(state + '/allocation-comparison.log')!.contains(arch + ' allocation sites unchanged: ' + total)
	}
	assert os.read_file(state + '/review-lifetimes.txt')!.contains('No remaining lifetime or locking blockers')
	for arch in ['aarch64', 'x86_64'] {
		elf := os.read_bytes(state + '/vinix-' + arch)!
		assert elf[..4] == [u8(127), `E`, `L`, `F`] && elf[4] == 2
		assert elf[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
	}
}
fn snapshot(repo string, bundle string, directory string) ! {
	for file in os.walk_ext(repo + '/' + directory, '.v') {
		copy_file(file, bundle + '/source/' + file[repo.len + 1..])!
	}
	if os.is_file(repo + '/' + directory + '/README.md') { copy_file(repo + '/' + directory + '/README.md', bundle + '/source/' + directory + '/README.md')! }
}
fn seal(repo string, state string) ! {
	check_logs(state)!
	bundle := state + '/bundle'; assert !os.exists(bundle) && !os.exists(state + '/bundle.tar.gz')
	paths := feature_paths(repo)!
	for path in paths {
		if path.starts_with('kernel/') { assert digest(repo + '/' + path)! == digest(state + '/kernel-build/' + path)!, path }
	}
	baseline := os.read_file(state + '/baseline.txt')!.trim_space()
	assert run('git', ['rev-parse', 'HEAD'], state + '/kernel-build')!.trim_space() == baseline
	assert run('git', ['rev-parse', 'HEAD'], state + '/kernel-baseline')!.trim_space() == baseline
	println(run(prior + '/bundle/inventory-check', ['check-inventory', prior + '/bundle', prior + '/inventory.json'], repo)!)
	for directory in ['kernel/gpu/agx', 'kernel/klock', 'kernel/katomic', 'kernel/aarch64/timer', 'kernel/sched',
		'tools/agx-re/g13contract', 'tests/agx-heap', 'tests/agx-g13-failure', 'tests/agx-heap-gc'] { snapshot(repo, bundle, directory)! }
	copy_file(repo + '/kernel/lib/math.v', bundle + '/source/kernel/lib/math.v')!
	for path in paths { assert digest(repo + '/' + path)! == digest(bundle + '/source/' + path)!, path }
	os.write_file(state + '/feature-paths.txt', paths.join('\n') + '\n')!
	copy_file(prior + '/bundle/inventory-check', bundle + '/inventory-check')!
	copy_file(prior + '/bundle/completion-check', bundle + '/completion-check')!
	copy_file(prior + '/bundle/source/tests/ios/evidence-delta-archive.v', bundle + '/source/tests/ios/evidence-delta-archive.v')!
	copy_file(prior + '/blob-aarch64.c', bundle + '/baseline/blob-aarch64.c')!
	copy_file(prior + '/kernel-allocs.log', bundle + '/baseline/kernel-allocs.log')!
	for directory in ['audit', 'negative', 'negative-final', 'negative-wire'] { os.cp_all(state + '/' + directory, bundle + '/' + directory, false)! }
	for file in os.ls(state)! {
		if os.is_file(state + '/' + file) && file != 'seal.log' { copy_file(state + '/' + file, bundle + '/' + file)! }
	}
	os.write_file(bundle + '/toolchain.txt', run('v', ['-version'], repo)! + run('cc', ['--version'], repo)! + run('ld.lld', ['--version'], repo)!)!
	checker := bundle + '/inventory-check'
	println(run(checker, ['record-inventory', bundle, state + '/inventory.json'], repo)!)
	println(run(checker, ['check-inventory', bundle, state + '/inventory.json'], repo)!)
	os.setenv('COPYFILE_DISABLE', '1', true)
	_ = run('tar', ['-czf', state + '/bundle.tar.gz', '-C', state, 'bundle', 'inventory.json'], repo)!
	os.mkdir_all(state + '/roundtrip')!
	_ = run('tar', ['-xzpf', state + '/bundle.tar.gz', '-C', state + '/roundtrip'], repo)!
	println(run(checker, ['check-inventory', state + '/roundtrip/bundle', state + '/roundtrip/inventory.json'], repo)!)
	for file in ['inventory.json', 'bundle.tar.gz', 'vinix-aarch64', 'vinix-x86_64', 'blob-aarch64.c'] { println(file + ' sha256 ' + digest(state + '/' + file)!) }
}
fn bind(repo string, state string, revision string) ! {
	assert revision.len == 40 && !os.exists(state + '/completion.txt')
	paths := feature_paths(repo)!
	mut all := paths.clone(); all << reports; all.sort()
	mut changed := run('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', revision], repo)!.split_into_lines(); changed.sort()
	assert all == changed
	mut receipt := ['feature commit ' + revision]
	for path in all {
		committed := run('git', ['show', revision + ':' + path], repo)!
		hash := sha256.sum(committed.bytes()).hex()
		assert hash == digest(repo + '/' + path)!, path
		if path in paths { assert hash == digest(state + '/bundle/source/' + path)!, path }
		receipt << path + ' sha256 ' + hash
	}
	for file in ['inventory.json', 'bundle.tar.gz', 'vinix-aarch64', 'vinix-x86_64', 'blob-aarch64.c'] {
		hash := digest(state + '/' + file)!
		assert os.read_file(repo + '/docs/m1-agx-heap-gc.md')!.contains(hash), file
		receipt << file + ' sha256 ' + hash
	}
	receipt << run(state + '/bundle/inventory-check', ['check-inventory', state + '/bundle', state + '/inventory.json'], repo)!.trim_space()
	os.write_file(state + '/completion.txt', receipt.join('\n') + '\n')!
	println('Committed feature paths and reports match the complete sealed bundle.')
}
fn main() {
	assert os.args.len in [3, 4]
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2]); assert !state.starts_with(repo + '/') && os.real_path(state) == state
	match os.args[1] {
		'--seal' { seal(repo, state)! }
		'--bind' { bind(repo, state, os.args[3])! }
		'--cleanup' {
			assert os.read_file(state + '/completion.txt')!.contains('Complete typed inventory receipt: PASS')
			baseline := os.read_file(state + '/baseline.txt')!.trim_space()
			for name in ['kernel-build', 'kernel-baseline'] {
				work := state + '/' + name
				assert os.real_path(work) == work && run('git', ['rev-parse', 'HEAD'], work)!.trim_space() == baseline
				_ = run('git', ['worktree', 'remove', '--force', work], repo)!
			}
			assert os.real_path(state + '/roundtrip') == state + '/roundtrip'
			os.rmdir_all(state + '/roundtrip')!
			println('Removed only the two private worktrees and verified archive restoration; complete bundles and archives retained.')
		}
		else { panic('usage: evidence --seal|--bind|--cleanup STATE [COMMIT]') }
	}
}
