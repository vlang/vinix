// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os

// Execute each caller's actual publication window. The surrounding security,
// overlay copy-up and event machinery belong to the native guest suites.
fn publication_extracts(root string, work string, source string) ! {
	normal := source.all_after('// Assign through its existing slot:').all_after('\n\tchildren_lock.acquire()').all_before('\n\tif unsafe { new_node != 0 }')
	mut out := 'module fs\nfn fixture_normal(mut old_parent_of VFSNode, old_basename string, mut old_node VFSNode, mut new_parent_of VFSNode, new_basename string, new_node &VFSNode) ? {\n'
	out += 'guarded := rename_before_publish(mut old_parent_of.filesystem, old_parent_of, old_basename, old_node, new_parent_of, new_basename, new_node, 0)?\nchildren_lock.acquire()' + normal + '\n}\n'
	exchange := source.all_after('if flags & rename_exchange != 0 {').all_after('\n\t\tguarded :=').all_before('\n\t\tfirst_cookie :=')
	out += 'fn fixture_exchange(mut old_parent_of VFSNode, old_basename string, mut old_node VFSNode, mut new_parent_of VFSNode, new_basename string, mut new_node VFSNode, flags int) ? {\nguarded :=' + exchange + '\n}\n'
	overlay := os.read_file(root + '/kernel/fs/overlay.v')!
	window := overlay.all_after('\n\tguarded := overlay_storage_rename').all_before('\n\tnames_adopted = true')
	out += 'fn fixture_overlay(mut old_upper VFSNode, old_name string, mut real VFSNode, mut new_upper VFSNode, new_name string, replaced_real &VFSNode, mut old_dir VFSNode, mut old_node VFSNode, mut new_dir VFSNode, replaced &VFSNode, mut old_whiteout VFSNode) ? {\nupper_name := new_name.clone()\nmerged_name := new_name.clone()\nwhiteout_name := if old_whiteout != unsafe { nil } && voidptr(old_whiteout.parent) != voidptr(old_upper) { old_name.clone() } else { "" }\nguarded := overlay_storage_rename' + window + '\n}\n'
	whiteout := overlay.all_after('\n  guarded := rename_before_publish(mut work.filesystem, work, whiteout.name').all_before('\n  adopted = true')
	out += 'fn fixture_whiteout(mut work VFSNode, mut whiteout VFSNode, mut upper_dir VFSNode, name string, mut node VFSNode, mut dir VFSNode) ? {\nfinal_name := name.clone()\nguarded := rename_before_publish(mut work.filesystem, work, whiteout.name' + whiteout + '\n_ = previous\n}\n'
	created := overlay.all_after('\n  guarded := rename_before_publish(mut work.filesystem, work, real.name').all_before('\n  adopted = true')
	out += 'fn fixture_created(mut work VFSNode, mut real VFSNode, mut upper VFSNode, node &VFSNode) ? {\nfinal_name := node.name.clone()\nguarded := rename_before_publish(mut work.filesystem, work, real.name' + created + '\n}\n'
	os.write_file(work + '/fs/publication_extract.v', out)!
}
