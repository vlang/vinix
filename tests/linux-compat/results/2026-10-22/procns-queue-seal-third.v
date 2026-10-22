import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const base_commit = 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'
const queue_ownership_commit = 'ec5631d664a8148c063b1ef9ac3f9657a3a0386a'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn git(tree string, args []string) !string {
	mut p := os.new_process('git')
	mut command := ['-C', tree]
	command << args
	p.set_args(command)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp().trim_space()
	p.wait()
	assert p.code == 0, output
	p.close()
	return output
}

fn main() {
	queue := area + '/queue-fix'
	commit := os.read_file(queue + '/commit.txt')!.trim_space()
	assert commit.len == 40 && commit != base_commit
	assert !os.exists(area + '/queue-candidate-inputs.json') && !os.exists(area + '/source-manifest3.json')
	mut inputs := {'kernel_commit': commit, 'base_commit': base_commit, 'queue_ownership_commit': queue_ownership_commit, 'purpose': 'Exact isolated cf642 plus kernel/fs/removed.v full-drain queue buffer ownership transfer and allocation-audit annotation; unchanged frozen2 fixture ELF'}
	mut artifacts := [area + '/qualify3.v', area + '/qualify3', area + '/seal-third.v', area + '/queue-fix-build.v', area + '/queue-fix-q2.v', area + '/queue-fix-review.v', area + '/procns-check', '/Users/alex/code/vinix/tests/linux-compat/procns-check.v', queue + '/commit.txt', queue + '/base.txt', queue + '/queue-commit.txt', queue + '/source-review.md', queue + '/q1-ec5631d664a8/archive.sha256']
	for name in os.ls(queue)! {
		if name.starts_with('q2-') && os.is_file(queue + '/' + name) { artifacts << queue + '/' + name }
	}
	for arch in ['arm', 'x86'] {
		tree := queue + '/kernel-' + arch
		assert git(tree, ['rev-parse', 'HEAD'])! == commit
		assert git(tree, ['status', '--porcelain', '--untracked-files=no'])! == ''
		assert os.read_file(queue + '/head-' + arch + '.log')!.trim_space() == commit
		assert os.read_file(queue + '/clean-' + arch + '.log')!.trim_space() == ''
		assert git(tree, ['rev-parse', commit + '^'])! == queue_ownership_commit
		assert git(tree, ['rev-parse', queue_ownership_commit + '^'])! == base_commit
		assert git(tree, ['diff', '--name-only', base_commit, commit])! == 'kernel/fs/removed.v'
		assert git(tree, ['diff', '--name-only', queue_ownership_commit, commit])! == 'kernel/fs/removed.v'
		annotation_diff := git(tree, ['diff', '--format=', '--unified=0', queue_ownership_commit, commit, '--', 'kernel/fs/removed.v'])!
		mut added := []string{}
		mut removed := []string{}
		for line in annotation_diff.split_into_lines() {
			if line.starts_with('+') && !line.starts_with('+++') { added << line[1..].trim_space() }
			if line.starts_with('-') && !line.starts_with('---') { removed << line[1..].trim_space() }
		}
		assert added == ['items = []RetiredItem{len: due} @[freed]'] && removed == ['items = []RetiredItem{len: due}'], annotation_diff
		inputs[arch + ':source_directory'] = tree
		inputs[arch + ':head'] = commit
		inputs[arch + ':tracked_status'] = 'clean'
		inputs[arch + ':source_diff'] = queue + '/source-' + arch + '.diff'
		assert os.read_file(queue + '/committed-' + arch + '.log')!.trim_space() == git(tree, ['diff', base_commit, commit, '--', 'kernel/fs/removed.v'])!
		for path in [tree + '/kernel/fs/removed.v', queue + '/removed-after-' + arch + '.v', queue + '/source-' + arch + '.diff', queue + '/committed-' + arch + '.log', queue + '/committed-' + arch + '.status', queue + '/clean-' + arch + '.log', queue + '/clean-' + arch + '.status', queue + '/head-' + arch + '.log', queue + '/head-' + arch + '.status', queue + '/diff-check-' + arch + '.log', queue + '/diff-check-' + arch + '.log.status'] { artifacts << path }
		for profile in ['track', 'prod'] {
			prefix := arch + '-' + profile
			kernel := queue + '/' + prefix + '/kernel'
			blob := queue + '/' + prefix + '/blob.c'
			status := queue + '/build-' + prefix + '.log.status'
			log := queue + '/build-' + prefix + '.log'
			assert os.read_file(status)!.trim_space() == '0'
			assert os.read_file(queue + '/generated-review-' + prefix + '.status')!.trim_space() == '0'
			inputs[prefix + ':kernel_directory'] = kernel
			inputs[prefix + ':kernel_sha256'] = digest(kernel + '/bin/vinix')!
			inputs[prefix + ':blob_sha256'] = digest(blob)!
			inputs[prefix + ':build_status'] = '0'
			inputs[prefix + ':build_status_path'] = status
			inputs[prefix + ':build_log'] = log
			inputs[prefix + ':source_diff'] = queue + '/source-' + arch + '.diff'
			artifacts << [kernel + '/bin/vinix', blob, status, log, queue + '/inputs-' + prefix + '.sha256']
			artifacts << [queue + '/generated-review-' + prefix + '.status', queue + '/generated-review-' + prefix + '.log', queue + '/generated-review-' + prefix + '.sha256', queue + '/generated-reaper-' + prefix + '.c']
		}
	}
	for path in artifacts { inputs['artifact:' + path] = digest(path)! }
	os.write_file(area + '/queue-candidate-inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	mut manifest := json2.decode[map[string]string](os.read_file(area + '/source-manifest2.json')!)!
	for path in artifacts { manifest[path] = digest(path)! }
	manifest[area + '/queue-candidate-inputs.json'] = digest(area + '/queue-candidate-inputs.json')!
	manifest[area + '/source-manifest2.json'] = digest(area + '/source-manifest2.json')!
	os.write_file(area + '/source-manifest3.json', json2.encode(manifest, prettify: true) + '\n')!
	println('Q=' + commit + ' candidate_inputs=' + digest(area + '/queue-candidate-inputs.json')! + ' manifest3=' + digest(area + '/source-manifest3.json')!)
}
