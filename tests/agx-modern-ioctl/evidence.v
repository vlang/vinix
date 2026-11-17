// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const baseline = '612f3032a27ab253800be6a1f8464d898b8beabd'
const kernel_paths = ['kernel/gpu/agx/driver/driver.v', 'kernel/gpu/agx/file/file.v',
	'kernel/gpu/agx/file/modern.v', 'kernel/gpu/agx/file/modern_submit.v',
	'kernel/gpu/agx/params/modern.v', 'kernel/gpu/agx/submission/modern.v',
	'kernel/gpu/agx/workqueue/workqueue.v']

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn run(program string, args []string, folder string) !string {
	mut p := os.new_process(program)
	p.set_args(args)
	p.set_work_folder(folder)
	p.set_redirect_stdio_merged()
	p.run()
	out := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { return error('${program}: exit ${code}: ${out}') }
	return out
}

fn feature_paths(repo string) []string {
	mut paths := kernel_paths.clone()
	paths << ['tests/agx-async/fixture/gpu/agx/file/host.v', 'tests/agx-async/fixture/gpu/agx/gpu/gpu.v',
		'tests/agx-async/run.v', 'tests/agx-file-close/fixture/drm/drm.v',
		'tests/agx-file-close/fixture/gpu/agx/file/host.v',
		'tests/agx-file-close/fixture/gpu/agx/gpu/gpu.v',
		'tests/agx-file-close/fixture/gpu/agx/workqueue/workqueue.v',
		'tests/agx-file-close/fixture/memory/memory.v',
		'tests/agx-file-close/fixture/usercopy/usercopy.v', 'tests/agx-file-close/run.v',
		'tests/agx-file-close/test.v', 'tools/agx-re/g13contract/queue_reference.v',
		'tools/agx-re/g13contract/queue_reference_test.v', 'tools/agx-re/m1parity/audit.v',
		'tools/agx-re/m1parity/core_test.v', 'tools/agx-re/m1parity/README.md']
	for path in os.walk_ext(repo + '/tests/agx-modern-ioctl', '.v') {
		paths << path[repo.len + 1..]
	}
	paths << 'tests/agx-modern-ioctl/README.md'
	paths.sort()
	return paths
}

fn copy_file(source string, target string) ! {
	os.mkdir_all(os.dir(target))!
	if os.exists(target) {
		assert digest(source)! == digest(target)!, target
		return
	}
	os.cp(source, target)!
}

fn check_results(state string) ! {
	assert os.read_file(state + '/unit-scoped.log')!.contains('74 passed, 74 total')
	async_log := os.read_file(state + '/async-complete.log')!
	assert async_log.contains('modern 64-command ioctl') && async_log.contains('700 copy/OOM/retry/drain cases pass')
	close_log := os.read_file(state + '/close-complete.log')!
	assert close_log.contains('1200 real mapping checks') && close_log.contains('modern queue/GEM ioctls')
	assert os.read_file(state + '/measure-complete.log')!.count('retained_blocks=0 retained_bytes=0') == 6
	assert os.read_file(state + '/measure-boxed.log')!.count('retained_blocks=2000 retained_bytes=3584000') == 6
	assert os.read_file(state + '/negative-qualified.log')!.count('compiled; designated modern ABI/copy/USC/cleanup assertion rejected') == 4
	assert os.read_file(state + '/check-selftest-final.log')!.contains('Six native boxing/free/copy/USC/transfer/registration mutations rejected')
	assert os.read_file(state + '/check-arm-final.log')!.contains('18 bodies reject implicit allocations')
	assert os.read_file(state + '/check-x86.log')!.contains('x86 generated C matches baseline')
	assert os.read_file(state + '/check-allocations.log')!.contains('Allocation sites unchanged by file/kind')
	assert os.read_file(state + '/packet.log')!.contains('28 records and every field match')
	assert os.read_file(state + '/audit.log')!.contains('Comparison scope: legacy compatibility declarations')
	assert os.read_file(state + '/audit.log')!.contains('not_equivalent')
	assert !os.read_file(state + '/audit.log')!.contains('FAILED:')
	assert os.read_file(state + '/review-lifetimes.txt')!.contains('No lifetime blockers found')
	for arch in ['aarch64', 'x86_64'] {
		elf := os.read_bytes(state + '/vinix-' + arch)!
		assert elf[..4] == [u8(127), `E`, `L`, `F`] && elf[4] == 2
		assert elf[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
	}
}

fn seal(repo string, state string) ! {
	check_results(state)!
	bundle := state + '/bundle'
	assert !os.exists(bundle) && !os.exists(state + '/bundle.tar.gz')
	os.mkdir_all(bundle + '/source')!
	for path in kernel_paths {
		assert digest(repo + '/' + path)! == digest(state + '/kernel-build/' + path)!, path
	}
	assert os.read_file(state + '/baseline.txt')!.trim_space() == baseline
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-signoff-20261117'
	checker := prior + '/bundle/archive-check'
	os.write_file(state + '/prior-signoff-check.log', run(checker, [
		'check-archive-root',
		prior + '/bundle.tar.gz',
		'66716262b0958e18261269b5ae9f8ad1e6431569326b2cbafd812f32988dc883',
		prior + '/bundle',
	], repo)!)!
	_ = run('git', ['archive', '-o', state + '/source.tar', baseline, 'kernel', 'tools/agx-re',
		'tests/agx-async', 'tests/agx-file-close', 'tests/agx-queue-records',
		'tests/agx-workqueue-records', 'tests/agx-g13-failure', 'tests/agx-packet', 'tests/drm-wire',
		'tests/linuxkpi/hosttest', 'tests/kernel-allocs', 'tests/ios/swift-staging-archive.v'], repo)!
	_ = run('tar', ['-xf', state + '/source.tar', '-C', bundle + '/source'], repo)!
	for path in feature_paths(repo) {
		os.mkdir_all(os.dir(bundle + '/source/' + path))!
		os.cp(repo + '/' + path, bundle + '/source/' + path)!
		assert digest(repo + '/' + path)! == digest(bundle + '/source/' + path)!, path
	}
	for arch in ['aarch64', 'x86_64'] {
		for row in os.read_file(state + '/inputs-' + arch + '.txt')!.split_into_lines() {
			if row == '' { continue }
			parts := row.split(' sha256 ')
			assert parts.len == 2 && parts[0].starts_with('kernel/') && !parts[0].contains('/../')
			path := parts[0]
			assert digest(state + '/kernel-build/' + path)! == parts[1], arch + ': ' + path
			os.mkdir_all(os.dir(bundle + '/source/' + path))!
			os.cp(state + '/kernel-build/' + path, bundle + '/source/' + path)!
			assert digest(bundle + '/source/' + path)! == parts[1], arch + ': ' + path
		}
	}
	for path in os.walk_ext(state + '/audit/source/vinix', '.v') {
		relative := path[(state + '/audit/source/vinix/').len..]
		assert digest(path)! == digest(bundle + '/source/' + relative)!, relative
	}
	os.write_file(state + '/feature-paths.txt', feature_paths(repo).join('\n') + '\n')!
	for directory in ['audit', 'audit-before-scope', 'packet', 'negative', 'negative-qualified',
		'before-stack-fix', 'before-value-snapshot'] {
		os.cp_all(state + '/' + directory, bundle + '/' + directory, false)!
	}
	for file in os.ls(state)! {
		if file == 'seal.log' || !os.is_file(state + '/' + file) { continue }
		copy_file(state + '/' + file, bundle + '/' + file)!
	}
	copy_file(checker, bundle + '/archive-check')!
	os.write_file(bundle + '/toolchain.txt', run('v', ['-version'], repo)! + run('cc', ['--version'], repo)!)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	println(run(bundle + '/archive-check', [bundle, state + '/bundle.tar.gz', state + '/roundtrip'], repo)!)
	archive_hash := digest(state + '/bundle.tar.gz')!
	for root in [bundle, state + '/roundtrip/bundle'] {
		println(run(bundle + '/archive-check', ['check-archive-root', state + '/bundle.tar.gz',
			archive_hash, root], repo)!)
	}
	println('archive sha256 ' + archive_hash)
	println('inventory sha256 ' + digest(state + '/bundle.tar.gz.inventory.txt')!)
}

fn bind(repo string, state string, revision string) ! {
	mut expected := feature_paths(repo)
	expected << ['docs/m1-agx-modern-dispatch.md', 'docs/m1-agx-parity.md']
	expected.sort()
	mut actual := run('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', revision], repo)!.trim_space().split_into_lines()
	actual.sort()
	assert actual == expected
	mut lines := ['feature commit ' + revision]
	for path in expected {
		committed := run('git', ['show', revision + ':' + path], repo)!
		hash := sha256.sum(committed.bytes()).hex()
		assert hash == digest(repo + '/' + path)!, path
		if !path.starts_with('docs/') {
			assert hash == digest(state + '/bundle/source/' + path)!, path
		}
		lines << path + ' sha256 ' + hash
	}
	assert !os.exists(state + '/completion.txt')
	os.write_file(state + '/completion.txt', lines.join('\n') + '\n')!
	println('Committed modern ABI sources/reports match the sealed evidence.')
}

fn main() {
	assert os.args.len in [3, 4]
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert os.real_path(state) == state && !state.starts_with(repo + '/')
	match os.args[1] {
		'--seal' {
			assert os.args.len == 3
			seal(repo, state)!
		}
		'--bind' {
			assert os.args.len == 4
			bind(repo, state, os.args[3])!
		}
		else { panic('usage: evidence --seal STATE | --bind STATE COMMIT') }
	}
}
