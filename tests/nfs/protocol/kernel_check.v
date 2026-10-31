// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Read-only assembly of the production kernel into a temporary architecture
// tree. No build files, dependency checkouts or other worktrees are changed.
fn assemble_kernel(root string, work string) ! {
	source := root + '/kernel'
	os.mkdir_all(work)!
	for path in os.walk_ext(source, '.v') {
		rel := path[source.len+1..]
		if rel.starts_with('obj/') || rel.starts_with('aarch64/') || rel.starts_with('apple/') || rel.starts_with('devicetree/') || rel.starts_with('drm/') || rel.starts_with('gpu/') || rel.starts_with('dev/pointerdev/') || rel == 'syscall/common.v' || rel.ends_with('_arm64.v') || rel.ends_with('_aarch64.v') { continue }
		target := work + '/' + rel
		os.mkdir_all(os.dir(target))!
		os.symlink(path, target)!
	}
	os.cp(source + '/v.mod', work + '/v.mod')!
}
