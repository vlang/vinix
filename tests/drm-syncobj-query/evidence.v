// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const prior = '/Users/alex/.local/state/vinix/omarchy-m1-timeline-chain-20261117'
const owned = ['kernel/drm/drm.v', 'kernel/drm/ioctl/ioctl.v', 'kernel/drm/syncobj/chain.v',
	'kernel/drm/syncobj_query.v', 'tests/drm-syncobj-wait/run.v', 'tools/agx-re/g13contract/query_test.v']

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
	for path in os.walk_ext(repo + '/tests/drm-syncobj-query', '.v') { files << path[repo.len + 1..] }
	files << 'tests/drm-syncobj-query/README.md'
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
	assert os.read_file(state + '/host-final/drm-wait.log')!.contains('DRM timeline QUERY: 7400 checks')
	assert os.read_file(state + '/host-final/drm-wait.log')!.contains('Asahi sync lookup: 18600 checks')
	assert os.read_file(state + '/host-final/reference.log')!.contains('10368 production QUERY values match')
	assert os.read_file(state + '/contracts.log')!.contains('72 passed, 72 total')
	assert os.read_file(state + '/native-check.log')!.count('four QUERY/registration/dispatch bodies reject hidden allocation') == 2
	for index in 0 .. 3 {
		assert os.exists(state + '/negative/case-${index}')
		assert os.read_file(state + '/negative/case-${index}.log')!.contains('query_checks.v:')
	}
	current, totals := allocation_counts(os.read_file(state + '/kernel-allocs.log')!)
	old, old_totals := allocation_counts(os.read_file(prior + '/bundle/qualified/kernel-allocs.log')!)
	assert current == old
	assert totals == old_totals.map(it.replace('841 source files', '842 source files').replace('814 source files', '815 source files'))
	os.write_file(state + '/allocation-comparison.txt', 'Every file/kind allocation count matches the chain baseline. One shared source added; existing allowance failures remain.\n' + totals.join('\n') + '\n')!
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
	previous_hash := '0c9d92e39b3cf9bf48a2bfffc86cb3f51e6f840d64aba3ed3113bb20f822b3bc'
	os.write_file(bundle + '/prior-check.log', run(bundle + '/archive-check', ['check-archive-root', prior + '/bundle.tar.gz', previous_hash, prior + '/bundle'])!)!
	for name in ['host-final', 'negative', 'contracts-source'] {
		copy_directory(state + '/' + name, bundle, state + '/copy-tmp/' + name + '.tar')!
	}
	for name in os.ls(state)! {
		if os.is_dir(state + '/' + name) || name.starts_with('archive-') || name.starts_with('bundle.') { continue }
		if name.ends_with('.log') || name.ends_with('.txt') || name.ends_with('.c') || name.ends_with('.v')
			|| name.ends_with('.tar') || name.starts_with('vinix-') { os.cp(state + '/' + name, bundle + '/' + name)! }
	}
	_ = run('git', ['-C', repo, 'archive', '-o', bundle + '/baseline-tests.tar', '0b9e112f8982754269b845809f1a6a73b486ff81',
		'tests/drm-syncobj-wait', 'tests/drm-timeline-chain', 'tests/agx-file-close/fixture/klock',
		'tests/agx-async/fixture/katomic', 'tests/agx-async/fixture/event', 'tests/agx-async/fixture/memory',
		'tests/agx-async/fixture/sched', 'tests/agx-async/fixture/time'])!
	os.write_file(bundle + '/review.txt', 'Read-only lifetime review /root/timeline_chain_lifetime_review: No blockers.\nAll object identities precede output; per-entry head sampling and unordered-context progress match upstream. Retained metadata covers namespace removal/reuse. Generated C keeps inline arrays and output points on stack; owned storage freed on every exit. Native allocation/failure precedence differs; capability stays disabled pending other operations.\n')!
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
	expected << ['docs/m1-agx-syncobj-query.md', 'docs/m1-agx-parity.md']
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
	println('Committed QUERY feature matches the complete sealed source; archive rechecked after commit.')
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
