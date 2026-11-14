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

	// Another clone can advance the remote without putting its tip in this
	// clone's object database. The hook must fetch it and still reject deleted
	// artifacts, leaving tracking refs and FETCH_HEAD untouched on failure.
	git(['fetch', '-q', 'origin', 'master'])!
	fetch_head := git(['rev-parse', '--git-path', 'FETCH_HEAD'])!.trim_space()
	fetch_before := os.read_file(fetch_head)!
	peer := tmp + '/peer'
	git(['clone', '-q', '--branch', 'master', tmp + '/remote.git', peer])!
	git(['-C', peer, 'config', 'user.name', 'Source policy peer'])!
	git(['-C', peer, 'config', 'user.email', 'source-policy-peer@example.invalid'])!
	git(['-C', peer, 'config', 'commit.gpgSign', 'false'])!
	git(['-C', peer, 'config', 'core.hooksPath', '/dev/null'])!
	os.write_file(peer + '/peer.v', 'module main\n')!
	git(['-C', peer, 'add', 'peer.v'])!
	git(['-C', peer, 'commit', '-q', '-m', 'remote source'])!
	git(['-C', peer, 'push', '-q', 'origin', 'HEAD:master'])!
	unseen := git(['-C', peer, 'rev-parse', 'HEAD'])!.trim_space()
	assert os.exec(['git', 'cat-file', '-e', unseen]).exit_code != 0
	blocked := os.exec(['git', 'push', '--force-with-lease=refs/heads/master:' + unseen,
		'origin', 'HEAD:master'])
	assert blocked.exit_code != 0
	assert blocked.output.contains('fetching missing remote base ' + unseen), blocked.output
	assert blocked.output.contains('generated test result'), blocked.output
	git(['cat-file', '-e', unseen])!
	assert git(['rev-parse', 'origin/master'])!.trim_space() == base
	assert os.read_file(fetch_head)! == fetch_before
	assert git(['--git-dir=' + tmp + '/remote.git', 'rev-parse', 'master'])!.trim_space() == unseen

	// A clean update must pass too, including pushes made directly to a URL.
	git(['reset', '-q', '--hard', base])!
	os.write_file('fixture.v', 'module main\n// clean change\n')!
	git(['add', 'fixture.v'])!
	git(['commit', '-q', '-m', 'clean source'])!
	os.write_file(peer + '/peer.v', 'module main\n// another remote change\n')!
	git(['-C', peer, 'commit', '-qam', 'another remote source'])!
	git(['-C', peer, 'push', '-q', 'origin', 'HEAD:master'])!
	next_unseen := git(['-C', peer, 'rev-parse', 'HEAD'])!.trim_space()
	assert os.exec(['git', 'cat-file', '-e', next_unseen]).exit_code != 0
	clean := git(['push', '--force-with-lease=refs/heads/master:' + next_unseen,
		tmp + '/remote.git', 'HEAD:master'])!
	assert clean.contains('fetching missing remote base ' + next_unseen), clean
	git(['cat-file', '-e', next_unseen])!
	assert os.read_file(fetch_head)! == fetch_before
	assert git(['--git-dir=' + tmp + '/remote.git', 'rev-parse', 'master'])!.trim_space() == git(['rev-parse', 'HEAD'])!.trim_space()
}
