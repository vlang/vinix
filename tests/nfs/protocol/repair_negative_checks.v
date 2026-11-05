// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os

fn rejected_regression(work string, v string, name string, assertion string) ! {
	program := work + '/negative-' + name
	checked([v, '-enable-globals', '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', program, work])!
	mut child := os.new_process(program)
	child.set_redirect_stdio()
	child.run()
	output := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	code := child.code
	child.close()
	os.write_file(program + '.log', output)!
	if code == 0 || !output.contains(assertion) { return error('negative control did not trip expected regression: ' + name + '\n' + output) }
	println('NFS negative control rejected old behavior: ${name} exit=${code}; log=${program}.log')
}

// Mutate only disposable assembled sources. Each mutant restores one reviewed
// pre-fix behavior; compiling successfully is required before rejection counts.
fn repair_negative_checks(work string, v string) ! {
	path := work + '/fs/nfs.v'
	original := os.read_file(path)!
	defer { os.write_file(path, original) or {} }
	old_keys := original.replace("memory.free(lookup_child(node, '.'))\n\t\t\t\tmemory.free(lookup_child(node, '..'))", "for key, child in node.children { if key == '.' || key == '..' { unsafe { free(child) } } }")
	if old_keys == original { return error('missing failed-cleanup mutation anchor') }
	os.write_file(path, old_keys)!
	rejected_regression(work, v, 'cleanup-key-clones', 'objects == 0')!
	os.write_file(path, original)!
	guard_path := work + '/fs/rename_publication.v'
	guard := os.read_file(guard_path)!
	defer { os.write_file(guard_path, guard) or {} }
	no_guard := guard.all_before('fn rename_before_publish(') + 'fn rename_before_publish(mut filesystem FileSystem, old_parent &VFSNode, old_name string, source &VFSNode, new_parent &VFSNode, new_name string, destination &VFSNode, flags int) ?bool {\nfilesystem.rename(old_parent, old_name, new_parent, new_name, flags)?\nreturn false\n}\nfn rename_after_publish(' + guard.all_after('fn rename_after_publish(')
	os.write_file(guard_path, no_guard)!
	rejected_regression(work, v, 'rename-unlock-before-publication', '!r.removed')!
	os.write_file(guard_path, guard)!
	old_statfs := original.replace('if !r.backend.usable() { return none }\n\tr.backend.client.fsstat', 'if !r.backend.usable() { return resource.FileSystemStat{} }\n\tr.backend.client.fsstat').replace('r.backend.failure(); return none }\n\treturn resource.FileSystemStat{', 'r.backend.failure(); return resource.FileSystemStat{} }\n\treturn resource.FileSystemStat{')
	if old_statfs == original { return error('missing statfs mutation anchor') }
	os.write_file(path, old_statfs)!
	rejected_regression(work, v, 'statfs-successful-default', 'rc == errno.err')!
	os.write_file(path, original)!
}
