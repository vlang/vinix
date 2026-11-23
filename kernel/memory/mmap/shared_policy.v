// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import proc
import resource

fn uses_file_policy(local &MmapRangeLocal) bool {
	res := local.global.resource
	return local.flags & map_anonymous == 0
		&& res != unsafe { nil } && res is resource.SharedMappingPolicy
}

fn explicit_policy(local &MmapRangeLocal, address u64) proc.NumaPolicy {
	if local.shared_anonymous() {
		mut global := local.global
		global.shadow_pagemap.l.acquire()
		defer { global.shadow_pagemap.l.release() }
		return global.shared_policies.lookup(shadow_address(local, address))
	}
	if uses_file_policy(local) {
		mut res := local.global.resource
		mode, mask := resource.shared_mapping_policy(mut res, u64(local.offset) + (address - local.base))
		return proc.NumaPolicy{mode: mode, mask: mask}
	}
	return local.policy
}

fn replace_shared_policy(local &MmapRangeLocal, start u64, end u64, policy proc.NumaPolicy) ? {
	mut global := local.global
	if local.shared_anonymous() {
		begin := shadow_address(local, start)
		global.shadow_pagemap.l.acquire()
		defer { global.shadow_pagemap.l.release() }
		global.shared_policies.replace(global.shadow_pagemap.kernel_owner, begin, begin + (end - start), policy)?
	} else if uses_file_policy(local) {
		begin := u64(local.offset) + (start - local.base)
		mut res := global.resource
		resource.set_shared_mapping_policy(mut res, begin, begin + (end - start), policy.mode, policy.mask)?
	}
}
