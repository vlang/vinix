// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const baseline = 'bf309feea4dc9ef2cde667d02ed83fcc5464216c'
const prior = '/Users/alex/.local/state/vinix/omarchy-m1-modern-dispatch-20261117'
const overlay = 'kernel/gpu/agx/submission/modern.v'

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
	if code != 0 { return error('${program}: ${code}: ${out}') }
	return out
}

fn feature_paths(repo string) []string {
	mut paths := [overlay, 'tests/agx-async/run.v', 'tests/agx-sync-zero/README.md']
	for path in os.walk_ext(repo + '/tests/agx-sync-zero', '.v') { paths << path[repo.len + 1..] }
	paths.sort()
	return paths
}

fn counts(source string) (map[string]int, []string) {
	mut sites := map[string]int{}
	mut totals := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') { totals << line }
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]
		space := tail.index(' ') or { continue }
		location := tail[..space].split(':')
		if location.len != 2 || location[0].int() <= 0 || location[1].int() <= 0 { continue }
		sites[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert sites.len > 100 && totals.len == 2
	return sites, totals
}

fn validate(state string) ! {
	log := os.read_file(state + '/async-final.log')!
	assert log.contains('AGX zero-point inputs: 160 scheduler cases')
	assert log.contains('AGX async: ioctl staging') && log.contains('700 copy/OOM/retry/drain cases pass')
	assert os.read_file(state + '/negative.log')!.contains('Original committed stager compiled and was rejected')
	assert os.read_file(state + '/reference-qualified.log')!.contains('4000 zero-point calls preserve the pointer')
	assert os.read_file(state + '/measure.log')!.count('retained_blocks=0 retained_bytes=0') == 6
	assert os.read_file(state + '/check-arm-final.log')!.contains('only the modern sync stager changes')
	assert os.read_file(state + '/check-x86.log')!.contains('x86 generated C matches baseline')
	assert os.read_file(state + '/check-adapter.log')!.contains('18 bodies reject implicit allocations')
	assert os.read_file(state + '/review.txt')!.contains('No blockers')
	current, current_totals := counts(os.read_file(state + '/kernel-allocs.log')!)
	old, old_totals := counts(os.read_file(prior + '/kernel-allocs.log')!)
	assert current == old && current_totals == old_totals
	os.write_file(state + '/allocation-comparison.txt', 'Every allocation file/kind count and both architecture totals match baseline.\n' + current_totals.join('\n') + '\n')!
	for arch in ['aarch64', 'x86_64'] {
		elf := os.read_bytes(state + '/vinix-' + arch)!
		assert elf[..4] == [u8(127), `E`, `L`, `F`] && elf[4] == 2
		assert elf[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
	}
}

fn seal(repo string, state string) ! {
	validate(state)!
	bundle := state + '/bundle'
	assert !os.exists(bundle) && !os.exists(state + '/bundle.tar.gz')
	assert os.read_file(state + '/baseline.txt')!.trim_space() == baseline
	assert digest(repo + '/' + overlay)! == digest(state + '/kernel-build/' + overlay)!
	checker := prior + '/bundle/archive-check'
	os.write_file(state + '/prior-archive-check.log', run(checker, [
		'check-archive-root',
		prior + '/bundle.tar.gz',
		'b04eecebd2a4aba070f6148dc7b85799240eac645cd24dc8a0deb0b79f19a0cf',
		prior + '/bundle',
	], repo)!)!
	os.mkdir_all(bundle + '/source')!
	_ = run('git', ['archive', '-o', state + '/source.tar', baseline, 'kernel', 'build-support',
		'tools/sourcecommand', 'tests/native-generators', 'tests/kernel-allocs',
		'tests/linuxkpi/hosttest', 'tests/agx-async', 'tests/agx-modern-ioctl', 'tests/agx-g13-failure',
		'tests/agx-queue-records', 'tests/ios/swift-staging-archive.v'], repo)!
	_ = run('tar', ['-xf', state + '/source.tar', '-C', bundle + '/source'], repo)!
	for path in feature_paths(repo) {
		os.mkdir_all(os.dir(bundle + '/source/' + path))!
		os.cp(repo + '/' + path, bundle + '/source/' + path)!
		assert digest(repo + '/' + path)! == digest(bundle + '/source/' + path)!
	}
	for arch in ['aarch64', 'x86_64'] {
		for row in os.read_file(state + '/inputs-' + arch + '.txt')!.split_into_lines() {
			if row == '' { continue }
			parts := row.split(' sha256 ')
			assert parts.len == 2 && parts[0].starts_with('kernel/') && !parts[0].contains('/../')
			path := parts[0]
			assert digest(state + '/kernel-build/' + path)! == parts[1]
			os.mkdir_all(os.dir(bundle + '/source/' + path))!
			os.cp(state + '/kernel-build/' + path, bundle + '/source/' + path)!
			assert digest(bundle + '/source/' + path)! == parts[1]
		}
		os.cp(prior + '/blob-' + arch + '.c', bundle + '/baseline-' + arch + '.c')!
		assert digest(prior + '/blob-' + arch + '.c')! == digest(bundle + '/baseline-' + arch + '.c')!
	}
	os.write_file(state + '/feature-paths.txt', feature_paths(repo).join('\n') + '\n')!
	for path in os.ls(state)! {
		if path in ['bundle', 'kernel-build', 'tmp', 'source.tar', 'seal.log'] { continue }
		if os.is_file(state + '/' + path) {
			os.cp(state + '/' + path, bundle + '/' + path)!
		} else {
			os.cp_all(state + '/' + path, bundle + '/' + path, false)!
		}
	}
	os.cp(checker, bundle + '/archive-check')!
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
	expected << ['docs/m1-agx-sync-zero.md', 'docs/m1-agx-parity.md']
	expected.sort()
	mut actual := run('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', revision], repo)!.trim_space().split_into_lines()
	actual.sort()
	assert actual == expected
	mut lines := ['feature commit ' + revision]
	for path in expected {
		committed := run('git', ['show', revision + ':' + path], repo)!
		hash := sha256.sum(committed.bytes()).hex()
		assert hash == digest(repo + '/' + path)!
		if !path.starts_with('docs/') {
			assert hash == digest(state + '/bundle/source/' + path)!
		}
		lines << path + ' sha256 ' + hash
	}
	archive_hash := digest(state + '/bundle.tar.gz')!
	lines << run(state + '/bundle/archive-check', ['check-archive-root', state + '/bundle.tar.gz',
		archive_hash, state + '/bundle'], repo)!
	lines << 'archive sha256 ' + archive_hash
	os.write_file(state + '/completion.txt', lines.join('\n') + '\n')!
	println('Committed feature bytes match the complete sealed bundle; post-commit archive check passed.')
}

fn main() {
	assert os.args.len >= 3 && os.args[1] in ['validate', 'seal', 'bind']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/')
	match os.args[1] {
		'validate' {
			assert os.args.len == 3
			validate(state)!
		}
		'seal' {
			assert os.args.len == 3
			seal(repo, state)!
		}
		else {
			assert os.args.len == 4
			bind(repo, state, os.args[3])!
		}
	}
}
