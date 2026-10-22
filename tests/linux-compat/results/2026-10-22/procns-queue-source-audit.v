import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const folder = area + '/queue-fix'
const base = 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'
const q1 = 'ec5631d664a8148c063b1ef9ac3f9657a3a0386a'
const q2 = 'bd9aa1bc1d04eac1ce31e02ce8914969294566ff'

fn git(args []string, tree string) !string {
	mut p := os.new_process('git')
	p.set_args(args)
	p.set_work_folder(tree)
	p.set_redirect_stdio_merged()
	p.run()
	out := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	assert code == 0
	return out
}

fn main() {
	assert os.read_file(folder + '/commit.txt')!.trim_space() == q2
	mut records := ['Source audit of isolated queue revision ' + q2, 'Base ' + base + '; prior runtime fix ' + q1]
	for suffix in ['x86', 'arm'] {
		tree := folder + '/kernel-' + suffix
		assert git(['rev-parse', 'HEAD'], tree)!.trim_space() == q2
		assert git(['rev-parse', q2 + '^'], tree)!.trim_space() == q1
		assert git(['rev-parse', q1 + '^'], tree)!.trim_space() == base
		assert git(['status', '--porcelain', '--untracked-files=no'], tree)! == ''
		assert git(['diff', '--name-only', base, q2], tree)!.trim_space() == 'kernel/fs/removed.v'
		before := git(['show', base + ':kernel/fs/removed.v'], tree)!
		old := '\tmut items := []RetiredItem{len: due} @[freed]\n\t// Transfer the original owned strings. V deep-clones a string-bearing\n\t// struct pushed directly from an array index, losing the original names.\n\tunsafe { C.memcpy(items.data, removed_items.data, usize(due) * sizeof(RetiredItem)) }\n\tremoved_items.delete_many(0, due)'
		new := '\tmut items := []RetiredItem{} @[freed]\n\tif due == removed_items.len {\n\t\t// Move the whole buffer when drained. Retiring and callbacks use a new\n\t\t// queue after unlock; the detached batch owns and frees the old buffer.\n\t\titems = unsafe { removed_items }\n\t\tremoved_items = []RetiredItem{}\n\t} else {\n\t\titems = []RetiredItem{len: due} @[freed]\n\t\t// Transfer the original owned strings. V deep-clones a string-bearing\n\t\t// struct pushed directly from an array index, losing the original names.\n\t\tunsafe { C.memcpy(items.data, removed_items.data, usize(due) * sizeof(RetiredItem)) }\n\t\tremoved_items.delete_many(0, due)\n\t}'
		assert before.count(old) == 1
		after := os.read_file(tree + '/kernel/fs/removed.v')!
		assert after == before.replace(old, new)
		prior := git(['show', q1 + ':kernel/fs/removed.v'], tree)!
		assert after == prior.replace('items = []RetiredItem{len: due}\n', 'items = []RetiredItem{len: due} @[freed]\n')
		records << suffix + ': clean exact Q2; aggregate one-file diff; partial-drain callbacks, grace, reference checks and final frees unchanged; Q1→Q2 assignment annotation only.'
		records << sha256.sum(after.bytes()).hex() + '  ' + tree + '/kernel/fs/removed.v'
	}
	records << 'PASS: Q2 aggregate one-file drain ownership and annotation-only followup.'
	log := area + '/queue-source-audit.log'
	assert !os.exists(log)
	os.write_file(log, records.join('\n') + '\n')!
	os.write_file(log + '.status', '0\n')!
	println(records.join('\n'))
}
