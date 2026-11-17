// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const prior = '/Users/alex/.local/state/vinix/omarchy-m1-fake-fences-20261117'
const baseline = '5648deb6a83989698af3f42f659511727004a812'
const owned = ['kernel/drm/gem/gem.v', 'kernel/drm/gem/advice.v', 'kernel/gpu/agx/file/file.v', 'kernel/gpu/agx/file/modern.v', 'tests/agx-file-close/run.v', 'tests/agx-file-close/fixture/drm/gem/gem.v', 'tests/agx-modern-ioctl/checks.v', 'tests/agx-modern-ioctl/README.md', 'tools/agx-re/g13contract/gem_advice_test.v']

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
	for path in os.walk_ext(repo + '/tests/agx-gem-advice', '.v') { files << path[repo.len + 1..] }
	files << 'tests/agx-gem-advice/README.md'
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
 host := os.read_file(state + '/host-reviewed/host.log')!
 for token in ['GEM advice: 96', 'AGX modern VM_BIND: 1200', 'AGX file close:'] { assert host.contains(token), token }
 for index, token in ['advice validation and ownership precedence', 'advice validation and ownership precedence', 'advice lookup reference must be released on every exit', 'advice state must change only on success'] {
  root := state + '/negative-reviewed/case-' + index.str()
  assert os.exists(root + '/host') && os.exists(root + '/host.c')
  assert os.read_file(root + '/host.log')!.contains(token)
 }
 assert os.read_file(state + '/measure-reviewed/host.log')!.count('retained_blocks=0 retained_bytes=0') == 3
 assert os.read_file(state + '/reference/oracle.log')! == os.read_file(state + '/reference/native.log')!
 assert os.read_file(state + '/reference/native.log')!.split_into_lines().len == 20481
 assert os.read_file(state + '/contracts.log')!.contains('78 passed, 78 total')
 native := os.read_file(state + '/native-check-complete.log')!
 assert native.contains('aarch64: advice/helper/handler have no hidden allocations') && native.contains('x86_64: advice and AGX backend pruned')
 current, totals := counts(os.read_file(state + '/kernel-allocs.log')!)
 old, old_totals := counts(os.read_file(prior + '/bundle/kernel-allocs.log')!)
 assert current == old && totals == old_totals.map(it.replace('852 source files', '853 source files').replace('824 source files', '825 source files'))
 os.write_file(state + '/allocation-comparison.txt', 'Every file/kind count matches the preceding complete bundle. One GEM source added on both architectures; existing allowance failures remain.\n' + totals.join('\n') + '\n')!
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
		'96fe38b238aac899dc2106d42f07658a6ebad6b38729f90bf62b877a4671df55', prior + '/bundle'])!)!
	for name in ['host-reviewed', 'negative-reviewed', 'measure-reviewed', 'trace', 'contracts-source', 'reference'] {
		copy_directory(state + '/' + name, bundle, state + '/copy-tmp/' + name + '.tar')!
	}
	for name in os.ls(state)! {
		if os.is_dir(state + '/' + name) || name.starts_with('archive-') || name.starts_with('bundle.') { continue }
		if name.ends_with('.log') || name.ends_with('.txt') || name.ends_with('.c') || name.ends_with('.v') || name.ends_with('.tar') || name.starts_with('vinix-') { os.cp(state + '/' + name, bundle + '/' + name)! }
	}
	_ = run('git', ['-C', repo, 'archive', '-o', bundle + '/baseline-tests.tar', baseline,
		'tests/drm-syncobj-wait', 'tests/drm-syncobj-query', 'tests/drm-binary-transfer', 'tests/drm-timeline-wait',
		'tests/drm-timeline-signal', 'tests/drm-timeline-chain', 'tests/drm-timeline-transfer', 'tests/agx-async',
		'tests/agx-queue-records', 'tests/agx-file-close', 'tests/agx-modern-ioctl', 'tests/agx-queue-scs', 'tests/agx-workqueue-records', 'tests/agx-g13-failure/fixture/katomic', 'tests/drm-wire/fixture/errno'])!
	os.write_file(state + '/archive-create.log', run(bundle + '/archive-check', [bundle, state + '/bundle.tar.gz', state + '/roundtrip'])!)!
	hash := digest(state + '/bundle.tar.gz')!
	mut checks := []string{}
	for root in [bundle, state + '/roundtrip/bundle'] { checks << run(bundle + '/archive-check', ['check-archive-root', state + '/bundle.tar.gz', hash, root])! }
	os.write_file(state + '/archive-roots.log', checks.join('\n'))!
	println('archive sha256 ' + hash + '\ninventory sha256 ' + digest(state + '/bundle.tar.gz.inventory.txt')!)
}
fn bind(repo string, state string, revision string) ! {
	mut expected := paths(repo)
	expected << ['docs/m1-agx-gem-advice.md', 'docs/m1-agx-parity.md']; expected.sort()
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
	println('Committed GEM-advice sources match the complete sealed bundle; archive rechecked after commit.')
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
			assert run('git', ['-C', work, 'diff', '--name-only'])!.trim_space().split_into_lines() == ['kernel/drm/gem/gem.v', 'kernel/gpu/agx/file/file.v', 'kernel/gpu/agx/file/modern.v']
			_ = run('git', ['-C', repo, 'worktree', 'remove', '--force', work])!
			println('Removed only task build worktree; archive, full restoration and earlier diagnostics retained.')
		}
	}
}
