import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const qdir = area + '/queue-fix'
const q1 = 'ec5631d664a8148c063b1ef9ac3f9657a3a0386a'
const base = 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'

fn run(args []string, folder string, log string) !string {
	mut p := os.new_process('git')
	p.set_args(args)
	p.set_work_folder(folder)
	p.set_redirect_stdio_merged()
	p.run()
	out := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, out)!
	os.write_file(log + '.status', '${code}\n')!
	assert code == 0, log
	return out
}

fn main() {
	archive := qdir + '/q1-' + q1[..12]
	assert !os.exists(archive)
	os.mkdir_all(archive)!
	// Freeze all Q1 root records and profile snapshots before any rebuild.
	for entry in os.ls(qdir)! {
		path := qdir + '/' + entry
		if os.is_file(path) { os.cp(path, archive + '/' + entry)! }
	}
	for label in ['x86-track', 'arm-track', 'x86-prod', 'arm-prod'] {
		os.mv(qdir + '/' + label, archive + '/' + label)!
	}
	for entry in os.ls(area)! {
		if (entry.starts_with('qf-allocs-') || entry.starts_with('qf-copy-') || entry == 'qf-inventory.v' || entry == 'qf-inventory' || entry.starts_with('qf-inventory-compile-') || entry.starts_with('queue-fix-')) && os.is_file(area + '/' + entry) {
			os.cp(area + '/' + entry, archive + '/' + entry)!
		}
	}
	mut pins := []string{}
	mut paths := os.walk_ext(archive, '')
	paths.sort()
	for path in paths {
		if os.is_file(path) { pins << sha256.sum(os.read_bytes(path)!).hex() + '  ' + path }
	}
	os.write_file(archive + '/archive.sha256', pins.join('\n') + '\n')!
	old := '\t\titems = []RetiredItem{len: due}\n'
	new := '\t\titems = []RetiredItem{len: due} @[freed]\n'
	for suffix in ['x86', 'arm'] {
		tree := qdir + '/kernel-' + suffix
		assert run(['rev-parse', 'HEAD'], tree, qdir + '/q2-parent-' + suffix + '.log')!.trim_space() == q1
		assert run(['status', '--porcelain', '--untracked-files=no'], tree, qdir + '/q2-before-' + suffix + '.log')! == ''
		path := tree + '/kernel/fs/removed.v'
		text := os.read_file(path)!
		assert text.count(old) == 1
		os.write_file(path, text.replace(old, new))!
		run(['diff', '--check'], tree, qdir + '/q2-diff-check-' + suffix + '.log')!
		diff := run(['diff', '--', 'kernel/fs/removed.v'], tree, qdir + '/q2-annotation-' + suffix + '.diff')!
		assert diff.contains('-\t\titems = []RetiredItem{len: due}\n+\t\titems = []RetiredItem{len: due} @[freed]')
		println(diff)
	}
	message := qdir + '/q2-commit-message.txt'
	os.write_file(message, 'Linux compatibility: annotate partial retirement batch ownership\n\nKeep the existing partial-drain allocation marked freed after moving its assignment into the conditional branch. The allocation inventory detects assignment annotations separately from the empty declaration. Ownership and runtime behavior are unchanged; the detached batch is freed after callbacks.\n')!
	x86 := qdir + '/kernel-x86'
	run(['commit', '--file', message, '--', 'kernel/fs/removed.v'], x86, qdir + '/q2-commit.log')!
	q2 := run(['rev-parse', 'HEAD'], x86, qdir + '/q2-head-x86.log')!.trim_space()
	assert q2.len == 40 && q2 != q1
	arm := qdir + '/kernel-arm'
	assert os.read_file(x86 + '/kernel/fs/removed.v')! == os.read_file(arm + '/kernel/fs/removed.v')!
	run(['reset', '--mixed', q2], arm, qdir + '/q2-adopt-arm.log')!
	for suffix in ['x86', 'arm'] {
		tree := qdir + '/kernel-' + suffix
		assert run(['status', '--porcelain', '--untracked-files=no'], tree, qdir + '/q2-clean-' + suffix + '.log')! == ''
		assert run(['rev-parse', 'HEAD'], tree, qdir + '/q2-final-head-' + suffix + '.log')!.trim_space() == q2
		os.cp(tree + '/kernel/fs/removed.v', qdir + '/removed-after-' + suffix + '.v')!
		run(['diff', base, q2, '--', 'kernel/fs/removed.v'], tree, qdir + '/source-' + suffix + '.diff')!
	}
	os.write_file(qdir + '/commit.txt', q2 + '\n')!
	os.write_file(qdir + '/queue-commit.txt', q2 + '\n')!
	println('Q1 archived at ' + archive)
	println('Q2 ' + q2)
}
