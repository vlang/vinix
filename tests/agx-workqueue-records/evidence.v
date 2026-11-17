// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

const prior = '/Users/alex/.local/state/vinix/omarchy-m1-queue-records-20261117'
const reports = ['docs/m1-agx-parity.md', 'docs/m1-agx-workqueue-records.md']
const overlays = ['kernel/gpu/agx/workqueue/workqueue.v', 'kernel/gpu/agx/file/file.v', 'kernel/gpu/agx/fake/driver.v']
const artifacts = ['inventory.json', 'bundle.tar.gz', 'vinix-aarch64', 'vinix-x86_64', 'blob-aarch64.c']

fn run(program string, args []string, folder string) !string {
	mut p := os.new_process(program); p.set_args(args); p.set_work_folder(folder)
	p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 0 { return error(program + ': ' + out) }; return out
}
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn copy_file(source string, target string) ! {
	os.mkdir_all(os.dir(target))!
	if os.exists(target) { assert digest(source)! == digest(target)!, target; return }
	os.cp(source, target)!
}
fn paths(repo string) []string {
	mut result := overlays.clone()
	result << ['tests/agx-file-close/run.v', 'tests/agx-file-close/fixture/gpu/agx/file/host.v',
		'tests/agx-file-close/fixture/gpu/agx/workqueue/workqueue.v', 'tools/agx-re/g13contract/queue_priority.v',
		'tools/agx-re/g13contract/queue_priority_test.v', 'tools/agx-re/g13contract/orphan_queue.v', 'tools/agx-re/g13contract/logical_queue_test.v']
	for file in os.walk_ext(repo + '/tests/agx-workqueue-records', '.v') { result << file[repo.len + 1..] }
	result << 'tests/agx-workqueue-records/README.md'; result.sort(); return result
}
fn check_logs(state string) ! {
	assert os.read_file(state + '/host-final.log')!.contains('143 fake close/destroy cases')
	assert os.read_file(state + '/host-final.log')!.contains('unlock-before-free passed')
	close := os.read_file(state + '/close.log')!
	assert close.contains('51 native close/detached/shifted-owner cases') && close.contains('AGX file close: live jobs, failed/partial queue release')
	assert os.read_file(state + '/measure-baseline.log')!.contains('retained_blocks=10000 retained_bytes=12800000')
	assert os.read_file(state + '/measure.log')!.count('retained_blocks=0 retained_bytes=0') == 3
	assert os.read_file(state + '/unit.log')!.contains('75 passed, 75 total')
	assert os.read_file(state + '/negative-qualified.log')!.count('compiled; designated logical-queue lifetime assertion rejected') == 7
	check := os.read_file(state + '/check-arm.log')!
	assert check.contains('stable pointer snapshots') && check.contains('six free/snapshot/index/allocation/last-access mutations rejected')
	assert os.read_file(state + '/check-x86.log')!.contains('x86 generated C matches baseline')
	assert os.read_file(state + '/allocation-comparison.log')!.contains('only verified logical queue record site removed, ARM378 to377')
	assert os.read_file(state + '/g13.log')!.contains('G13 failure handling: PASS')
	assert os.read_file(state + '/unwind.log')!.contains('3640 constructor failure/success/quarantine cases')
	context := os.read_file(state + '/context.log')!
	assert context.contains('3672 real queue/heap/channel cases') && context.contains('1008 four-context FIFO/snapshot/failure cases')
	assert os.read_file(state + '/audit.log')!.contains('not_equivalent')
	assert os.read_file(state + '/reference.log')!.contains('TVB binding on slot acquisition or heap growth')
	assert os.read_file(state + '/review-lifetimes.txt')!.contains('No lifetime or ownership blockers found')
	for arch in ['aarch64', 'x86_64'] {
		elf := os.read_bytes(state + '/vinix-' + arch)!
		assert elf[..4] == [u8(127), `E`, `L`, `F`] && elf[4] == 2
		assert elf[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
	}
}
fn snapshot(repo string, bundle string, directory string) ! {
	for file in os.walk_ext(repo + '/' + directory, '.v') { copy_file(file, bundle + '/source/' + file[repo.len + 1..])! }
	if os.is_file(repo + '/' + directory + '/README.md') { copy_file(repo + '/' + directory + '/README.md', bundle + '/source/' + directory + '/README.md')! }
}
fn seal(repo string, state string) ! {
	check_logs(state)!
	cache := state + '/tmp'
	assert os.real_path(cache) == cache && !os.is_link(cache)
	os.rmdir_all(cache)!; os.mkdir_all(cache)!
	bundle := state + '/bundle'; assert !os.exists(bundle) && !os.exists(state + '/bundle.tar.gz')
	for path in overlays { assert digest(repo + '/' + path)! == digest(state + '/kernel-build/' + path)!, path }
	assert os.read_file(state + '/baseline.txt')!.trim_space() == 'bc40b06d096fc9626f25f5c8cbd519dfbc8cdf97'
	println(run(prior + '/bundle/inventory-check', ['check-inventory', prior + '/bundle', prior + '/inventory.json'], repo)!)
	for directory in ['kernel/gpu/agx', 'kernel/drm', 'kernel/sched', 'kernel/katomic', 'kernel/klock', 'kernel/aarch64/timer',
		'tests/agx-workqueue-records', 'tests/agx-queue-records', 'tests/agx-file-close', 'tests/agx-queue-unwind', 'tests/agx-context-defer', 'tests/agx-context-retire', 'tests/agx-teardown-gc', 'tests/agx-heap-cancel', 'tests/agx-heap-pressure',
		'tests/agx-worker', 'tests/agx-heap-gc', 'tests/agx-heap', 'tests/agx-g13-failure', 'tools/agx-re'] { snapshot(repo, bundle, directory)! }
	for file in os.walk_ext(state + '/audit/source/vinix', '.v') {
		rel := file[(state + '/audit/source/vinix/').len..]
		assert digest(file)! == digest(repo + '/' + rel)!, rel
	}
	for path in paths(repo) { assert digest(repo + '/' + path)! == digest(bundle + '/source/' + path)!, path }
	os.write_file(state + '/feature-paths.txt', paths(repo).join('\n') + '\n')!
	copy_file(prior + '/bundle/inventory-check', bundle + '/inventory-check')!
	copy_file(prior + '/bundle/completion-check', bundle + '/completion-check')!
	copy_file(prior + '/bundle/source/tests/ios/evidence-delta-archive.v', bundle + '/source/tests/ios/evidence-delta-archive.v')!
	for file in ['blob-aarch64.c', 'blob-x86_64.c', 'kernel-allocs.log'] { copy_file(prior + '/' + file, bundle + '/baseline/' + file)! }
	for directory in ['audit', 'negative', 'negative-qualified', 'baseline'] { os.cp_all(state + '/' + directory, bundle + '/' + directory, false)! }
	for file in os.ls(state)! { if os.is_file(state + '/' + file) && file != 'seal.log' { copy_file(state + '/' + file, bundle + '/' + file)! } }
	os.write_file(bundle + '/toolchain.txt', run('v', ['-version'], repo)! + run('cc', ['--version'], repo)! + run('ld.lld', ['--version'], repo)!)!
	checker := bundle + '/inventory-check'
	println(run(checker, ['record-inventory', bundle, state + '/inventory.json'], repo)!)
	println(run(checker, ['check-inventory', bundle, state + '/inventory.json'], repo)!)
	os.setenv('COPYFILE_DISABLE', '1', true)
	_ = run('tar', ['-czf', state + '/bundle.tar.gz', '-C', state, 'bundle', 'inventory.json'], repo)!
	os.mkdir_all(state + '/roundtrip')!
	_ = run('tar', ['-xzpf', state + '/bundle.tar.gz', '-C', state + '/roundtrip'], repo)!
	println(run(checker, ['check-inventory', state + '/roundtrip/bundle', state + '/roundtrip/inventory.json'], repo)!)
	for file in artifacts { println(file + ' sha256 ' + digest(state + '/' + file)!) }
}
fn bind(repo string, state string, revision string) ! {
	assert revision.len == 40 && !os.exists(state + '/completion.txt')
	feature := paths(repo); mut all := feature.clone(); all << reports; all.sort()
	mut changed := run('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', revision], repo)!.split_into_lines(); changed.sort()
	assert all == changed
	mut receipt := ['feature commit ' + revision]
	for path in all {
		data := run('git', ['show', revision + ':' + path], repo)!
		hash := sha256.sum(data.bytes()).hex(); assert hash == digest(repo + '/' + path)!, path
		if path in feature { assert hash == digest(state + '/bundle/source/' + path)!, path }
		receipt << path + ' sha256 ' + hash
	}
	for file in artifacts {
		hash := digest(state + '/' + file)!; assert os.read_file(repo + '/docs/m1-agx-workqueue-records.md')!.contains(hash), file
		receipt << file + ' sha256 ' + hash
	}
	receipt << run(state + '/bundle/inventory-check', ['check-inventory', state + '/bundle', state + '/inventory.json'], repo)!.trim_space()
	os.write_file(state + '/completion.txt', receipt.join('\n') + '\n')!
	println('Committed logical queue-record sources and reports match the complete sealed bundle.')
}
fn main() {
	assert os.args.len in [3, 4]
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2]); assert !state.starts_with(repo + '/') && os.real_path(state) == state
	match os.args[1] {
		'--seal' { seal(repo, state)! }
		'--bind' { assert os.args.len == 4; bind(repo, state, os.args[3])! }
		'--cleanup' {
			assert os.read_file(state + '/completion.txt')!.contains('Complete typed inventory receipt: PASS')
			work := state + '/kernel-build'
			assert os.real_path(work) == work && !os.is_link(work)
			assert run('git', ['rev-parse', 'HEAD'], work)!.trim_space() == os.read_file(state + '/baseline.txt')!.trim_space()
			_ = run('git', ['worktree', 'remove', '--force', work], repo)!
			assert os.real_path(state + '/roundtrip') == state + '/roundtrip' && !os.is_link(state + '/roundtrip')
			os.rmdir_all(state + '/roundtrip')!
			println('Removed only private worktree and verified archive restoration; complete bundles retained.')
		}
		else { panic('usage: evidence --seal|--bind|--cleanup STATE [COMMIT]') }
	}
}
