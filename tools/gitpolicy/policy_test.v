module gitpolicy

import os
import rand

fn test_output_policy_preserves_source_and_small_reports() {
	for path in ['tests/example/fixture.v', 'tests/example/fixtures/input.dat',
		'tests/example/results/source.v', 'tests/example/results/reference.c',
		'tests/example/results/change.patch', 'tests/example/results/README.md'] {
		assert reason(path, 100, '#include <stdlib.h>') == '', path
	}
	for path in ['tests/example/results/kernel/bin/vinix', 'tests/example/results/receipt.json',
		'tests/example/results/efivars.fd', 'tests/example/results/network.pcap',
		'tests/example/results/objects/abcd', 'tests/example/results/generated/blob.c'] {
		assert reason(path, 100, '') != '', path
	}
	assert reason('tests/example/results/fixture.c', 100, '// V comptime_definitions:') != ''
	assert reason('tests/example/results/README.md', max_report_size + 1, '') != ''
	assert reason('large.dat', max_blob_size, '') == ''
	assert reason('large.dat', max_blob_size + 1, '') != ''
}

fn test_audit_checks_deleted_versions_duplicate_blobs_and_merge_history() ! {
	original := os.getwd()
	tmp := os.join_path(os.temp_dir(), 'vinix-git-policy-test-' + rand.uuid_v4())
	os.mkdir(tmp)!
	os.chdir(tmp)!
	defer {
		os.chdir(original) or { panic(err) }
		os.rmdir_all(tmp) or { panic(err) }
	}
	git(['init', '-q'])!
	git(['config', 'user.name', 'Source policy test'])!
	git(['config', 'user.email', 'source-policy@example.invalid'])!
	git(['config', 'commit.gpgSign', 'false'])!
	git(['config', 'core.hooksPath', '/dev/null'])!
	git(['commit', '-q', '--allow-empty', '-m', 'base'])!
	base := git(['rev-parse', 'HEAD'])!.trim_space()
	branch := git(['symbolic-ref', '--short', 'HEAD'])!.trim_space()
	os.mkdir_all('tests/example')!
	os.write_file('tests/example/fixture.v', 'module main\n')!
	git(['add', '.'])!
	git(['commit', '-q', '-m', 'source'])!
	assert audit(base, 'HEAD')!.len == 0
	os.mkdir_all('tests/example/results/run with spaces')!
	os.write_file('tests/example/results/run with spaces/receipt\nname.json', '{}\n')!
	// This object already has a legitimate source path; still check its alias.
	os.write_file('tests/example/results/copied-binary', 'module main\n')!
	os.write_file('tests/example/results/fixture.c', '// V comptime_definitions:\n')!
	os.write_file('tests/example/large.dat', 'x'.repeat(int(max_blob_size + 1)))!
	git(['add', '.'])!
	git(['commit', '-q', '-m', 'outputs'])!
	git(['rm', '-qr', 'tests/example/results', 'tests/example/large.dat'])!
	git(['commit', '-q', '-m', 'remove outputs'])!
	assert audit(base, 'HEAD')!.len == 4
	git(['checkout', '-qb', 'side', base])!
	os.mkdir_all('tests/example/results')!
	os.write_file('tests/example/results/side.json', '{}\n')!
	git(['add', '.'])!
	git(['commit', '-q', '-m', 'side evidence'])!
	git(['checkout', '-q', branch])!
	git(['merge', '-q', '--no-ff', 'side', '-m', 'merge'])!
	violations := audit(base, 'HEAD')!
	assert violations.len == 5
	assert violations.any(it.file.path == 'tests/example/results/run with spaces/receipt\nname.json')
	assert violations.any(it.file.path == 'tests/example/results/copied-binary')
	assert !violations.any(it.file.path == 'tests/example/fixture.v')
	assert audit('', 'HEAD')!.len == 5
}

fn test_real_pre_push_hook_blocks_artifacts_before_local_remote_changes() ! {
	original := os.getwd()
	source_root := os.real_path(os.dir(@FILE) + '/../..')
	tmp := os.join_path(os.temp_dir(), 'vinix-pre-push-test-' + rand.uuid_v4())
	os.mkdir_all(tmp + '/work')!
	os.chdir(tmp + '/work')!
	defer {
		os.chdir(original) or { panic(err) }
		os.rmdir_all(tmp) or { panic(err) }
	}
	git(['init', '-q', '--bare', tmp + '/remote.git'])!
	git(['init', '-q'])!
	git(['config', 'user.name', 'Source policy test'])!
	git(['config', 'user.email', 'source-policy@example.invalid'])!
	git(['config', 'commit.gpgSign', 'false'])!
	git(['config', 'core.hooksPath', source_root + '/.githooks'])!
	os.symlink(source_root + '/tools', 'tools')!
	os.write_file('fixture.v', 'module main\n')!
	git(['add', 'fixture.v'])!
	git(['commit', '-q', '-m', 'source'])!
	base := git(['rev-parse', 'HEAD'])!.trim_space()
	git(['remote', 'add', 'origin', tmp + '/remote.git'])!
	git(['push', '-q', 'origin', 'HEAD:master'])!
	os.mkdir_all('tests/example/results')!
	os.write_file('tests/example/results/receipt.json', '{}\n')!
	git(['add', 'tests'])!
	git(['commit', '-q', '-m', 'artifact'])!
	git(['rm', '-qr', 'tests'])!
	git(['commit', '-q', '-m', 'delete artifact'])!
	push := os.exec(['git', 'push', 'origin', 'HEAD:master'])
	assert push.exit_code != 0
	assert push.output.contains('generated test result'), push.output
	assert git(['--git-dir=' + tmp + '/remote.git', 'rev-parse', 'master'])!.trim_space() == base
}
