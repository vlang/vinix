// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const prior = '/Users/alex/.local/state/vinix/omarchy-m1-timeline-transfer-20261117'
const baseline = '0d7a4df5b598242f4f6bbb77a914426459054714'
const owned = ['kernel/gpu/agx/fake/driver.v', 'kernel/gpu/agx/fake/fence.v',
	'tests/drm-syncobj-wait/run.v', 'tools/agx-re/g13contract/fake_fence_test.v']

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn run(program string, args []string) !string {
	mut p := os.new_process(program)
	p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	assert p.code == 0, program + ': ' + out
	p.close(); return out
}
fn paths(repo string) []string {
	mut files := owned.clone()
	for path in os.walk_ext(repo + '/tests/agx-fake-fences', '.v') { files << path[repo.len + 1..] }
	files << 'tests/agx-fake-fences/README.md'
	files.sort(); return files
}
fn counts(source string) (map[string]int, []string) {
	mut sites := map[string]int{}; mut totals := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') { totals << line }
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]; space := tail.index(' ') or { continue }
		sites[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert sites.len > 100 && totals.len == 2; return sites, totals
}
fn validate(state string) ! {
	host := os.read_file(state + '/host-complete/host.log')!
	for token in ['Fake fences: 48', 'Fake submission transaction: 16', 'Asahi sync lookup: 18600 checks'] { assert host.contains(token), token }
	for directory, token in {
		'case-0': 'independent fake jobs need distinct contexts'
		'case-1': 'exhausted contexts must reject fake submission'
		'case-2': 'fake fences cannot elide queue dependencies'
		'missing-vm-unwind': 'context exhaustion must unwind the VM pin'
	} {
		root := state + '/negative-complete/' + directory
		assert os.exists(root + '/host') && os.exists(root + '/host.c')
		assert os.read_file(root + '/host.log')!.contains(token)
	}
	assert os.read_file(state + '/contracts.log')!.contains('77 passed, 77 total')
	native := os.read_file(state + '/native-check.log')!
	assert native.contains('aarch64: helper has no hidden allocations') && native.contains('x86_64: fake backend and generic constructor pruned')
	current, totals := counts(os.read_file(state + '/kernel-allocs.log')!)
	old, old_totals := counts(os.read_file(prior + '/bundle/kernel-allocs.log')!)
	assert current == old && totals == old_totals.map(it.replace('851 source files', '852 source files'))
	os.write_file(state + '/allocation-comparison.txt', 'Every file/kind count matches the preceding complete bundle. ARM adds one source file; x86 prunes fake. Existing allowance failures remain.\n' + totals.join('\n') + '\n')!
	for arch in ['aarch64', 'x86_64'] {
		elf := os.read_bytes(state + '/vinix-' + arch)!
		assert elf[..4] == [u8(127), `E`, `L`, `F`] && elf[4] == 2
		assert elf[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
	}
	assert os.exists(state + '/review.txt')
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
	os.cp(prior + '/bundle/archive-check.v', bundle + '/archive-check.v')!
	os.write_file(bundle + '/prior-check.log', run(bundle + '/archive-check', ['check-archive-root', prior + '/bundle.tar.gz',
		'dfd6ef5c7f2f535591994dcc074134f5e348457b4c2e4253dcefc6a4f351813f', prior + '/bundle'])!)!
	for name in ['host-complete', 'negative-complete', 'contracts-source', 'reference'] {
		copy_directory(state + '/' + name, bundle, state + '/copy-tmp/' + name + '.tar')!
	}
	for name in os.ls(state)! {
		if os.is_dir(state + '/' + name) || name.starts_with('archive-') || name.starts_with('bundle.') { continue }
		if name.ends_with('.log') || name.ends_with('.txt') || name.ends_with('.c') || name.ends_with('.v') || name.ends_with('.tar') || name.starts_with('vinix-') { os.cp(state + '/' + name, bundle + '/' + name)! }
	}
	_ = run('git', ['-C', repo, 'archive', '-o', bundle + '/baseline-tests.tar', baseline,
		'tests/drm-syncobj-wait', 'tests/drm-syncobj-query', 'tests/drm-binary-transfer', 'tests/drm-timeline-wait',
		'tests/drm-timeline-signal', 'tests/drm-timeline-chain', 'tests/drm-timeline-transfer', 'tests/agx-async',
		'tests/agx-queue-records/stats_darwin.c.v', 'tests/agx-file-close/fixture/klock'])!
	os.write_file(state + '/archive-create.log', run(bundle + '/archive-check', [bundle, state + '/bundle.tar.gz', state + '/roundtrip'])!)!
	hash := digest(state + '/bundle.tar.gz')!
	mut checks := []string{}
	for root in [bundle, state + '/roundtrip/bundle'] { checks << run(bundle + '/archive-check', ['check-archive-root', state + '/bundle.tar.gz', hash, root])! }
	os.write_file(state + '/archive-roots.log', checks.join('\n'))!
	println('archive sha256 ' + hash + '\ninventory sha256 ' + digest(state + '/bundle.tar.gz.inventory.txt')!)
}
fn bind(repo string, state string, revision string) ! {
	mut expected := paths(repo)
	expected << ['docs/m1-agx-fake-fences.md', 'docs/m1-agx-parity.md']; expected.sort()
	mut actual := run('git', ['-C', repo, 'diff-tree', '--no-commit-id', '--name-only', '-r', revision])!.trim_space().split_into_lines()
	actual.sort(); assert actual == expected
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
	println('Committed fake-fence sources match the complete sealed bundle; archive rechecked after commit.')
}
fn main() {
	assert os.args.len >= 3 && os.args[1] in ['validate', 'seal', 'bind', 'cleanup']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/')
	match os.args[1] {
		'validate' { validate(state)! }
		'seal' { seal(repo, state)! }
		'bind' { assert os.args.len == 4; bind(repo, state, os.args[3])! }
		else {
			assert os.read_file(state + '/completion.txt')!.contains('Pinned archive and complete named root bytes, paths, types, modes and link targets: PASS')
			work := state + '/kernel-build'
			assert run('git', ['-C', work, 'rev-parse', 'HEAD'])!.trim_space() == baseline
			assert run('git', ['-C', work, 'diff', '--name-only'])!.trim_space() == 'kernel/gpu/agx/fake/driver.v'
			_ = run('git', ['-C', repo, 'worktree', 'remove', '--force', work])!
			println('Removed only task build worktree; archive, full restoration and earlier diagnostics retained.')
		}
	}
}
