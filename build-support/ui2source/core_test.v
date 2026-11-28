module ui2source

import os

fn inputs(path string) ! {
	for name in ['v.mod', 'ui/vml_compiled.v', 'examples/calculator/calculator.vml'] {
		os.mkdir_all(os.dir('${path}/${name}'))!
		os.write_file('${path}/${name}', 'fixture\n')!
	}
}

fn must_reject(root string, explicit string, remote string, pin string) {
	resolve_from(root, explicit, remote, pin) or { return }
	assert false, 'expected refusal'
}

fn test_exact_fetch_reuse_and_refusals() ! {
	base := temporary_directory(os.temp_dir())!
	defer { os.rmdir_all(base) or {} }
	remote := '${base}/remote with spaces'
	os.mkdir_all(remote)!
	git(remote, ['init'])!
	inputs(remote)!
	git(remote, ['add', '.'])!
	git(remote, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit',
		'-m', 'pinned fixture'])!
	pin := git(remote, ['rev-parse', 'HEAD'])!
	// Default branch advances beyond the requested commit.
	os.write_file('${remote}/newer', 'newer')!
	git(remote, ['add', '.'])!
	git(remote, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit',
		'-m', 'newer fixture'])!
	root := '${base}/project'
	path := resolve_from(root, '', remote, pin)!
	assert git(path, ['rev-parse', 'HEAD'])! == pin
	assert !os.exists('${path}/newer')
	// Reuse needs no remote, and cannot silently follow its default branch.
	assert resolve_from(root, '', '/nonexistent-remote', pin)! == path
	os.write_file('${path}/v.mod', 'dirty')!
	must_reject(root, '', remote, pin)
	assert os.read_file('${path}/v.mod')! == 'dirty'
	git(path, ['checkout', '--', 'v.mod'])!
	os.write_file('${path}/untracked', 'keep')!
	must_reject(root, '', remote, pin)
	os.rm('${path}/untracked')!
	os.write_file('${path}/.git/info/exclude', 'ignored\n')!
	os.write_file('${path}/ignored', 'keep')!
	must_reject(root, '', remote, pin)
	os.rm('${path}/ignored')!
	must_reject(root, '', remote, '0000000000000000000000000000000000000000')
	assert git(path, ['rev-parse', 'HEAD'])! == pin
	// A failed fetch leaves no destination and can be retried.
	lock_path := '${base}/failed/third_party/ui2.lock'
	os.mkdir_all(lock_path)!
	must_reject('${base}/failed', '', remote, pin)
	assert os.is_dir(lock_path)
	assert !os.exists('${base}/failed/third_party/ui2')
	os.rmdir(lock_path)!
	must_reject('${base}/failed', '', '/nonexistent-remote', pin)
	assert !os.exists('${base}/failed/third_party/ui2')
	assert os.ls('${base}/failed/third_party')! == []string{}
	// A clean pinned tree must still contain the required VML input.
	os.rm('${remote}/examples/calculator/calculator.vml')!
	git(remote, ['add', '.'])!
	git(remote, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit',
		'-m', 'missing VML'])!
	missing_pin := git(remote, ['rev-parse', 'HEAD'])!
	must_reject('${base}/missing-vml', '', remote, missing_pin)
	assert os.ls('${base}/missing-vml/third_party')! == []string{}
	// Concurrent resolvers may succeed or refuse a busy lock, but must not nest.
	a := spawn resolve_result('${base}/concurrent', remote, pin)
	b := spawn resolve_result('${base}/concurrent', remote, pin)
	first := a.wait()
	second := b.wait()
	assert first != '' || second != ''
	concurrent_path := '${base}/concurrent/third_party/ui2'
	assert git(concurrent_path, ['rev-parse', 'HEAD'])! == pin
	assert os.ls('${base}/concurrent/third_party')! == ['ui2']
	for entry in os.ls(concurrent_path)! {
		assert !entry.starts_with('.ui2-fetch-')
	}
}

fn resolve_result(root string, remote string, pin string) string {
	return resolve_from(root, '', remote, pin) or { '' }
}

fn test_publication_rejects_nonempty_destination() ! {
	base := temporary_directory(os.temp_dir())!
	defer { os.rmdir_all(base) or {} }
	source := '${base}/fetched'
	destination := '${base}/winner'
	os.mkdir(source)!
	os.mkdir(destination)!
	os.write_file('${source}/source', 'fetched')!
	os.write_file('${destination}/destination', 'winner')!
	mut rejected := false
	publish(source, destination) or { rejected = true }
	assert rejected
	assert os.read_file('${source}/source')! == 'fetched'
	assert os.read_file('${destination}/destination')! == 'winner'
	assert os.ls(source)! == ['source']
	assert os.ls(destination)! == ['destination']
}

fn test_override_precedence_and_unexpected_checkout() ! {
	assert revision == '293e845e2bf2557c7100996d82fcc23160e57dd9'
	base := temporary_directory(os.temp_dir())!
	defer { os.rmdir_all(base) or {} }
	root := '${base}/project'
	automatic := '${root}/third_party/ui2'
	inputs(automatic)!
	must_reject(root, '', '/nonexistent-remote', revision)
	// Explicit sources need not be Git checkouts or clean.
	assert resolve_from(root, automatic, '/nonexistent-remote', revision)! == automatic
	sibling := '${base}/ui2'
	inputs(sibling)!
	assert resolve_from(root, '', '/nonexistent-remote', revision)! == '${root}/../ui2'
	assert resolve_from(root, automatic, '/nonexistent-remote', revision)! == automatic
	must_reject(root, '${base}/missing', '/nonexistent-remote', revision)
	assert os.read_file('${automatic}/v.mod')! == 'fixture\n'
	os.rm('${automatic}/examples/calculator/calculator.vml')!
	must_reject(root, automatic, '/nonexistent-remote', revision)
}
