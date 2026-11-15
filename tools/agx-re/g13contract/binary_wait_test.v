module g13contract

import g13layout
import os

fn test_binary_wait_guard_rejects_snapshot_and_flag_regressions() {
	local := os.read_file(g13layout.repo_root() + '/kernel/drm/drm.v')!
	reference := 'int drm_syncobj_create(\nkzalloc_obj(struct drm_syncobj);\n' +
		'if (flags & DRM_SYNCOBJ_CREATE_SIGNALED) drm_syncobj_assign_null_handle(syncobj);\n' +
		'if (fence) drm_syncobj_replace_fence(syncobj, fence);\nEXPORT_SYMBOL(drm_syncobj_create)\n' +
		'drm_syncobj_wait_ioctl(\npossible_flags = DRM_SYNCOBJ_WAIT_FLAGS_WAIT_ALL |\n' +
		'DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT | DRM_SYNCOBJ_WAIT_FLAGS_WAIT_DEADLINE;\n' +
		'if (args->flags & ~possible_flags) return -EINVAL;\nif (args->count_handles == 0) return 0;\ndrm_syncobj_array_find();\n' +
		'drm_syncobj_timeline_wait_ioctl(\n' +
		'static int drm_syncobj_array_find(\ncopy_from_user(handles, user_handles);\n' +
		'syncobjs[i] = drm_syncobj_find();\nret = -ENOENT;\nstatic void drm_syncobj_array_free(\n' +
		'static signed long drm_syncobj_array_wait_timeout(\nfence = drm_syncobj_fence_get(syncobjs[i]);\n' +
		'DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT |\ntimeout = -EINVAL;\nentries[i].fence = fence;\n' +
		'do {\nfence = entries[i].fence;\ndma_fence_is_signaled(fence);\n* drm_timeout_abs_to_jiffies'
	check_binary_wait_contract(local, reference)!
	for token in ['if request.count_handles == 0 { return 0 }', 'usercopy.copy_from_user(',
		'syncobj.captured_fence(', 'syncobj.release_capture(', 'sched.reschedule()'] {
		if _ := check_binary_wait_contract(local.replace(token, ''), reference) { assert false, token }
	}
	if _ := check_binary_wait_contract(local.replace('known_flags :=', 'known_flags := ioctl.drm_syncobj_wait_available |'), reference) { assert false }
	if _ := check_binary_wait_contract(local.replace('syncobj.is_signaled(fence)', 'syncobj.is_signaled(obj.fence)'), reference) { assert false }
	if _ := check_binary_wait_contract(local, reference.replace('fence = entries[i].fence;', '')) { assert false }
}
