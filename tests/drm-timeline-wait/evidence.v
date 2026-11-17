// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const prior = '/Users/alex/.local/state/vinix/omarchy-m1-timeline-signal-20261117'
const owned = ['kernel/drm/drm.v', 'kernel/drm/ioctl/ioctl.v', 'kernel/drm/syncobj/syncobj.v',
	'kernel/drm/syncobj/chain.v', 'kernel/drm/syncobj/timeline_capture.v', 'kernel/drm/syncobj_timeline_wait.v', 'tests/drm-syncobj-wait/run.v', 'tools/agx-re/g13contract/timeline_wait_test.v']

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn run(program string, args []string) !string {
	mut p := os.new_process(program)
	p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	assert p.code == 0, program + ': ' + out
	p.close()
	return out
}

fn paths(repo string) []string {
	mut files := owned.clone()
	for path in os.walk_ext(repo + '/tests/drm-timeline-wait', '.v') { files << path[repo.len + 1..] }
	files << 'tests/drm-timeline-wait/README.md'
	files.sort()
	return files
}

fn allocation_counts(source string) (map[string]int, []string) {
	mut counts := map[string]int{}
	mut totals := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') { totals << line }
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]
		space := tail.index(' ') or { continue }
		counts[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert counts.len > 100 && totals.len == 2
	return counts, totals
}

fn validate(state string) ! {
	assert os.read_file(state + '/host-final/drm-wait.log')!.contains('DRM timeline WAIT: 1824 counted')
	assert os.read_file(state + '/host-final/drm-wait.log')!.contains('Asahi sync lookup: 18600 checks')
	assert os.read_file(state + '/host-final/reference.log')!.contains('21952 production timeline WAIT')
	assert os.read_file(state + '/measure/measure.log')!.count('retained_blocks=0 retained_bytes=0') == 9
	assert os.read_file(state + '/contracts.log')!.contains('74 passed, 74 total')
	assert os.read_file(state + '/native-check.log')!.count('timeline WAIT/registration bodies reject hidden allocations') == 2
	for index in 0 .. 3 {
		assert os.exists(state + '/negative-final/case-' + index.str())
		assert os.read_file(state + '/negative-final/case-' + index.str() + '.log')!.contains('timeline_wait_')
	}
	current, totals := allocation_counts(os.read_file(state + '/kernel-allocs.log')!)
	old, old_totals := allocation_counts(os.read_file(prior + '/bundle/kernel-allocs.log')!)
	assert current == old
	assert totals == old_totals.map(it.replace('844 source files', '846 source files').replace('817 source files', '819 source files'))
	os.write_file(state + '/allocation-comparison.txt', 'Every file/kind allocation count matches the SIGNAL baseline. Two shared sources added; existing allowance failures remain.\n' + totals.join('\n') + '\n')!
	for arch in ['aarch64', 'x86_64'] {
		elf := os.read_bytes(state + '/vinix-' + arch)!
		assert elf[..4] == [u8(127), `E`, `L`, `F`] && elf[4] == 2
		assert elf[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
	}
}

fn copy_directory(source string, target string, temporary string) ! {
	_ = run('tar', ['-cpf', temporary, '-C', os.dir(source), os.file_name(source)])!
	_ = run('tar', ['-xpf', temporary, '-C', target])!
}

fn seal(repo string, state string) ! {
	validate(state)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	bundle := state + '/bundle'
	assert !os.exists(bundle) && !os.exists(state + '/bundle.tar.gz')
	os.mkdir_all(bundle + '/source')!
	os.mkdir_all(state + '/copy-tmp')!
	for path in paths(repo) {
		os.mkdir_all(os.dir(bundle + '/source/' + path))!
		os.cp(repo + '/' + path, bundle + '/source/' + path)!
		if path.starts_with('kernel/') { assert digest(repo + '/' + path)! == digest(state + '/kernel-build/' + path)! }
	}
	os.cp(prior + '/bundle/archive-check', bundle + '/archive-check')!
	os.cp(repo + '/tests/ios/swift-staging-archive.v', bundle + '/archive-check.v')!
	previous_hash := '96e7024b318cfeebe29ff6225e5977a1f876cbdbd8d790156569852544b992f9'
	os.write_file(bundle + '/prior-check.log', run(bundle + '/archive-check', ['check-archive-root', prior + '/bundle.tar.gz', previous_hash, prior + '/bundle'])!)!
	for name in ['host-final', 'negative-final', 'measure', 'contracts-source'] {
		copy_directory(state + '/' + name, bundle, state + '/copy-tmp/' + name + '.tar')!
	}
	for name in os.ls(state)! {
		if os.is_dir(state + '/' + name) || name.starts_with('archive-') || name.starts_with('bundle.') { continue }
		if name.ends_with('.log') || name.ends_with('.txt') || name.ends_with('.c') || name.ends_with('.v')
			|| name.ends_with('.tar') || name.starts_with('vinix-') { os.cp(state + '/' + name, bundle + '/' + name)! }
	}
	_ = run('git', ['-C', repo, 'archive', '-o', bundle + '/baseline-tests.tar', 'd3ae11cef54ea7f2ea493ce02e4e86960817dbb6',
		'tests/drm-syncobj-wait', 'tests/drm-syncobj-query', 'tests/drm-timeline-signal', 'tests/drm-timeline-chain', 'tests/agx-queue-records/stats_darwin.c.v', 'tests/agx-file-close/fixture/klock',
		'tests/agx-async/fixture/katomic', 'tests/agx-async/fixture/event', 'tests/agx-async/fixture/memory',
		'tests/agx-async/fixture/sched', 'tests/agx-async/fixture/time'])!
	os.cp(state + '/review.txt', bundle + '/review.txt')!

	os.write_file(state + '/archive-create.log', run(bundle + '/archive-check', [bundle, state + '/bundle.tar.gz', state + '/roundtrip'])!)!
	hash := digest(state + '/bundle.tar.gz')!
	mut checks := []string{}
	for root in [bundle, state + '/roundtrip/bundle'] {
		checks << run(bundle + '/archive-check', ['check-archive-root', state + '/bundle.tar.gz', hash, root])!
	}
	os.write_file(state + '/archive-roots.log', checks.join('\n'))!
	println('archive sha256 ' + hash)
	println('inventory sha256 ' + digest(state + '/bundle.tar.gz.inventory.txt')!)
}

fn bind(repo string, state string, revision string) ! {
	mut expected := paths(repo)
	expected << ['docs/m1-agx-timeline-wait.md', 'docs/m1-agx-parity.md']
	expected.sort()
	mut actual := run('git', ['-C', repo, 'diff-tree', '--no-commit-id', '--name-only', '-r', revision])!.trim_space().split_into_lines()
	actual.sort()
	assert actual == expected
	mut receipt := ['feature commit ' + revision]
	for path in expected {
		hash := sha256.sum(run('git', ['-C', repo, 'show', revision + ':' + path])!.bytes()).hex()
		assert hash == digest(repo + '/' + path)!
		if !path.starts_with('docs/') { assert hash == digest(state + '/bundle/source/' + path)! }
		receipt << path + ' sha256 ' + hash
	}
	hash := digest(state + '/bundle.tar.gz')!
	receipt << run(state + '/bundle/archive-check', ['check-archive-root', state + '/bundle.tar.gz', hash, state + '/bundle'])!
	os.write_file(state + '/completion.txt', receipt.join('\n') + '\narchive sha256 ' + hash + '\n')!
	println('Committed timeline WAIT feature matches the complete sealed source; archive rechecked after commit.')
}

fn main() {
	assert os.args.len >= 3 && os.args[1] in ['validate', 'seal', 'bind']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/')
	match os.args[1] {
		'validate' { validate(state)! }
		'seal' { seal(repo, state)! }
		else { assert os.args.len == 4; bind(repo, state, os.args[3])! }
	}
}
