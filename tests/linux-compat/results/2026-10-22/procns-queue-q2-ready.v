import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/queue-fix'
const q2 = 'bd9aa1bc1d04eac1ce31e02ce8914969294566ff'

fn git(args []string, tree string, log string) !string {
	mut p := os.new_process('git')
	p.set_args(args)
	p.set_work_folder(tree)
	p.set_redirect_stdio_merged()
	p.run()
	out := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, out)!
	os.write_file(log + '.status', '${code}\n')!
	os.write_file(log.all_before_last('.log') + '.status', '${code}\n')!
	assert code == 0
	return out
}

fn main() {
	assert os.read_file(area + '/commit.txt')!.trim_space() == q2
	mut records := ['Final isolated revision ' + q2]
	for label in ['x86-track', 'arm-track', 'x86-prod', 'arm-prod'] {
		assert os.read_file(area + '/build-' + label + '.log.status')!.trim_space() == '0'
		assert os.read_file(area + '/generated-review-' + label + '.status')!.trim_space() == '0'
		manifest := os.read_file(area + '/inputs-' + label + '.sha256')!
		for row in manifest.split_into_lines() {
			parts := row.split_nth('  ', 2)
			assert parts.len == 2 && sha256.sum(os.read_bytes(parts[1])!).hex() == parts[0]
		}
		for artifact in ['kernel/bin/vinix', 'blob.c'] {
			path := area + '/' + label + '/' + artifact
			current := sha256.sum(os.read_bytes(path)!).hex()
			prior := sha256.sum(os.read_bytes(area + '/q1-ec5631d664a8/' + label + '/' + artifact)!).hex()
			records << label + ' ' + artifact + ' Q2=' + current + ' Q1=' + prior + ' identical=' + (current == prior).str()
		}
	}
	for suffix in ['x86', 'arm'] {
		tree := area + '/kernel-' + suffix
		assert git(['rev-parse', 'HEAD'], tree, area + '/head-' + suffix + '.log')!.trim_space() == q2
		assert git(['status', '--short', '--untracked-files=no'], tree, area + '/clean-' + suffix + '.log')! == ''
		assert git(['diff', 'cf6426cf16657a6db8d5be8062ef82f170c6b48b', q2, '--', 'kernel/fs/removed.v'], tree, area + '/committed-' + suffix + '.log')! == os.read_file(area + '/source-' + suffix + '.diff')!
	}
	records << 'PASS: four final Q2 build/profile snapshots, current digests, generated-C checks and clean exact source heads.'
	log := area + '/q2-ready.log'
	assert !os.exists(log)
	os.write_file(log, records.join('\n') + '\n')!
	os.write_file(log + '.status', '0\n')!
	println(records.join('\n'))
}
