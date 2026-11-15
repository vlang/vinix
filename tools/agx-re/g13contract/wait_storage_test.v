module g13contract

import g13layout
import os

fn test_wait_storage_guards_reject_capacity_caps_and_unchecked_lifetimes() {
	repo := g13layout.repo_root()
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	storage := os.read_file(repo + '/kernel/drm/wait_storage.v')!
	reference := 'static int drm_syncobj_array_find(\nkmalloc_array(count_handles, sizeof(*handles));\nreturn -ENOMEM;\n' +
		'copy_from_user(handles, user_handles);\nkmalloc_objs(*syncobjs, count_handles);\nkfree(handles);\n' +
		'static void drm_syncobj_array_free(\nstatic signed long drm_syncobj_array_wait_timeout(\n' +
		'entries = kzalloc_objs(*entries, count);\ntimeout = -ENOMEM;\ncleanup_entries:\n' +
		'drm_syncobj_remove_wait(syncobjs[i], &entries[i]);\nkfree(entries);\n* drm_timeout_abs_to_jiffies'
	check_wait_storage_contract(drm, storage, reference)!
	for token in ['(maximum - 15) / sizeof(u32)', 'objects_end > maximum - 15',
		'(maximum - captures_offset) / sizeof(syncobj.FenceCapture)', 'C.memset(allocation, 0, geometry.bytes)',
		'memory.free(buffer.allocation)'] {
		if _ := check_wait_storage_contract(drm, storage.replace(token, ''), reference) { assert false, token }
	}
	if _ := check_wait_storage_contract(drm.replace('defer { buffer.free_owned() }', ''), storage, reference) { assert false }
	if _ := check_wait_storage_contract(drm.replace('if request.count_handles > 64 {', 'if request.count_handles > 64 {\n\t\treturn -22\n} else if request.count_handles > 64 {'), storage, reference) { assert false }
	if _ := check_wait_storage_contract(drm, storage, reference.replace('kfree(entries);', '')) { assert false }
}
