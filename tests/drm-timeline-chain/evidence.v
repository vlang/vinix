// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const prior = '/Users/alex/.local/state/vinix/omarchy-m1-sync-storage-20261117'
const owned = ['kernel/drm/syncobj/chain.v', 'kernel/drm/syncobj/syncobj.v',
	'kernel/drm/syncobj/events.v', 'kernel/drm/syncobj/info.v', 'kernel/drm/sync_file_info.v', 'kernel/drm/sync_file_deadline.v',
	'kernel/gpu/agx/submission/modern.v', 'kernel/gpu/agx/submission/submission.v', 'kernel/gpu/agx/submission/sync_storage.v',
	'tests/agx-async/run.v', 'tests/agx-async/fixture/memory/memory.v', 'tests/agx-modern-ioctl/submission.v',
	'tests/agx-sync-zero/checks.v', 'tests/drm-syncobj-wait/run.v', 'tests/drm-syncobj-wait/fixture/memory/memory.v',
	'tools/agx-re/g13contract/fence_completion.v', 'tools/agx-re/g13contract/poll.v',
	'tools/agx-re/g13contract/info.v', 'tools/agx-re/g13contract/info_test.v']

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
	for path in os.walk_ext(repo + '/tests/drm-timeline-chain', '.v') { files << path[repo.len + 1..] }
	files << 'tests/drm-timeline-chain/README.md'
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

fn validate(root string) ! {
	state := root + '/qualified-host'
	assert os.read_file(state + '/host/check.log')!.contains('10000 reverse completions')
	assert os.read_file(state + '/reference.log')!.contains('41472 production lookups/readiness results match')
	assert os.read_file(state + '/async.log')!.contains('Modern timeline chains: every 1/3/64/65/129-record reservation failure')
	assert os.read_file(state + '/async.log')!.contains('AGX async: ioctl staging')
	assert os.read_file(state + '/drm-wait.log')!.contains('Sync-file chains: count/capacity/OOM')
	assert os.read_file(state + '/drm-wait.log')!.contains('Asahi sync lookup: 18600 checks')
	assert os.read_file(state + '/drm-fence.log')!.contains('800 success/error completions')
	assert os.read_file(state + '/measure.log')!.count('retained_blocks=0 retained_bytes=0') == 9
	assert os.read_file(state + '/contracts.log')!.contains('71 passed, 71 total')
	assert os.read_file(state + '/native-check.log')!.count('14 common allocation-sensitive bodies') == 2
	assert os.read_file(state + '/adapter-check.log')!.contains('Six native boxing/free/copy/USC/transfer/registration mutations rejected.')
	for index in 0 .. 2 { assert os.exists(root + '/negative-final/case-${index}/check') }
	assert os.read_file(root + '/negative-final/missing-cleanup.log')!.contains('memory.outstanding_chains() == before')
	current, totals := allocation_counts(os.read_file(state + '/kernel-allocs.log')!)
	old, old_totals := allocation_counts(os.read_file(prior + '/kernel-allocs.log')!)
	assert current == old
	assert totals == old_totals.map(it.replace('840 source files', '841 source files').replace('813 source files', '814 source files'))
	os.write_file(state + '/allocation-comparison.txt', 'Every file/kind count matches the preceding sync-storage build. One shared source added per architecture. Existing allowance failures remain.\n' + totals.join('\n') + '\n')!
	for arch in ['aarch64', 'x86_64'] {
		elf := os.read_bytes(state + '/vinix-' + arch)!
		assert elf[..4] == [u8(127), `E`, `L`, `F`] && elf[4] == 2
		assert elf[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
	}
}

// Preserve modes and symbolic links, including intentionally unresolved scoped
// source links. cp_all follows them and cannot copy these complete snapshots.
fn copy_directory(source string, target string, temporary string) ! {
	_ = run('tar', ['-cpf', temporary, '-C', os.dir(source), os.file_name(source)])!
	_ = run('tar', ['-xpf', temporary, '-C', target])!
}

fn seal(repo string, root string) ! {
	validate(root)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	bundle := root + '/bundle'
	assert !os.exists(bundle) && !os.exists(root + '/bundle.tar.gz')
	os.mkdir_all(bundle + '/source')!
	os.mkdir_all(bundle + '/qualified')!
	os.mkdir_all(root + '/copy-tmp')!
	for path in paths(repo) {
		os.mkdir_all(os.dir(bundle + '/source/' + path))!
		os.cp(repo + '/' + path, bundle + '/source/' + path)!
	}
	os.cp(prior + '/bundle/archive-check', bundle + '/archive-check')!
	os.cp(repo + '/tests/ios/swift-staging-archive.v', bundle + '/archive-check.v')!
	previous_hash := 'feed08607aa5a36a77f0b42f6ee3cf13b6e0ac6967b366a3d8f132ebc9ac0164'
	assert digest(prior + '/bundle.tar.gz')! == previous_hash
	os.write_file(bundle + '/prior-check.log', run(bundle + '/archive-check', ['check-archive-root',
		prior + '/bundle.tar.gz', previous_hash, prior + '/bundle'])!)!
	for name in os.ls(root + '/qualified-host')! {
		if name in ['kernel-build', 'tmp'] { continue }
		source := root + '/qualified-host/' + name
		if os.is_dir(source) {
			copy_directory(source, bundle + '/qualified', root + '/copy-tmp/' + name + '.tar')!
		} else { os.cp(source, bundle + '/qualified/' + name)! }
	}
	copy_directory(root + '/negative-final', bundle, root + '/copy-tmp/negative.tar')!
	os.mkdir_all(bundle + '/diagnostic-boxing')!
	for name in ['measure', 'measure.c', 'measure.log'] { os.cp(root + '/qualified/' + name, bundle + '/diagnostic-boxing/' + name)! }
	os.cp(root + '/qualified/kernel-build/kernel/gpu/agx/submission/sync_storage.v', bundle + '/diagnostic-boxing/sync_storage.v')!
	os.write_file(bundle + '/review.txt', 'Read-only lifetime review /root/timeline_chain_lifetime_review: No blockers.\nEmbedded parent-owned waiters, unlocked nonrecursive drain, publication-before-retention transfer, unpublished reservation cleanup, direct scalar cleanup reads, chain queue provenance, immutable captures and original-size zero-tail sync-file output reviewed.\nPublished metadata reclamation, legacy interoperability and hardware parity remain unqualified.\n')!
	for path in owned {
		if path.starts_with('kernel/') { assert digest(repo + '/' + path)! == digest(root + '/qualified-host/kernel-build/' + path)! }
	}
	os.write_file(root + '/archive-create.log', run(bundle + '/archive-check', [bundle, root + '/bundle.tar.gz', root + '/roundtrip'])!)!
	hash := digest(root + '/bundle.tar.gz')!
	mut checks := []string{}
	for path in [bundle, root + '/roundtrip/bundle'] {
		checks << run(bundle + '/archive-check', ['check-archive-root', root + '/bundle.tar.gz', hash, path])!
	}
	os.write_file(root + '/archive-roots.log', checks.join('\n'))!
	println('archive sha256 ' + hash)
	println('inventory sha256 ' + digest(root + '/bundle.tar.gz.inventory.txt')!)
}

fn bind(repo string, root string, revision string) ! {
	mut expected := paths(repo)
	expected << ['docs/m1-agx-timeline-chain.md', 'docs/m1-agx-parity.md']
	expected.sort()
	mut actual := run('git', ['-C', repo, 'diff-tree', '--no-commit-id', '--name-only', '-r', revision])!.trim_space().split_into_lines()
	actual.sort()
	assert actual == expected
	mut receipt := ['feature commit ' + revision]
	for path in expected {
		hash := sha256.sum(run('git', ['-C', repo, 'show', revision + ':' + path])!.bytes()).hex()
		assert hash == digest(repo + '/' + path)!
		if !path.starts_with('docs/') { assert hash == digest(root + '/bundle/source/' + path)! }
		receipt << path + ' sha256 ' + hash
	}
	hash := digest(root + '/bundle.tar.gz')!
	receipt << run(root + '/bundle/archive-check', ['check-archive-root', root + '/bundle.tar.gz', hash, root + '/bundle'])!
	os.write_file(root + '/completion.txt', receipt.join('\n') + '\narchive sha256 ' + hash + '\n')!
	println('Committed feature bytes match the complete sealed bundle; archive rechecked after commit.')
}

fn main() {
	assert os.args.len >= 3 && os.args[1] in ['validate', 'seal', 'bind']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	root := os.abs_path(os.args[2])
	assert !root.starts_with(repo + '/')
	match os.args[1] {
		'validate' { validate(root)! }
		'seal' { seal(repo, root)! }
		else { assert os.args.len == 4; bind(repo, root, os.args[3])! }
	}
}
