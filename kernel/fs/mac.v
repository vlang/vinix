// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import proc
import resource
import security
import errno

fn mac_node(node &VFSNode, access u32) ? {
	if node == unsafe { nil } || node.resource == unsafe { nil } { errno.set(errno.eacces); return none }
	mut res := node.resource
	security.mac_require(mut res, access)?
}

fn mac_path_access(access u32) u32 {
	mut mask := u32(0)
	if access & proc.policy_read != 0 { mask |= proc.mac_read }
	if access & proc.policy_write != 0 { mask |= proc.mac_write }
	if access & proc.policy_exec != 0 { mask |= proc.mac_execute }
	if access & (proc.policy_create | proc.policy_device | proc.policy_socket) != 0 { mask |= proc.mac_create }
	if access & (proc.policy_fattr | proc.policy_chown) != 0 { mask |= proc.mac_metadata }
	if access & proc.policy_inspect != 0 { mask |= proc.mac_inspect }
	return mask
}

fn mac_path_allowed(node &VFSNode, access u32) bool {
	mac_node(node, mac_path_access(access)) or { return false }
	return true
}

fn mac_creation(parent &VFSNode, mut node VFSNode) ? {
	mut parent_res := parent.resource
	mut child_res := node.resource
	security.mac_inherit(mut parent_res, mut child_res)?
}

fn mac_resource(mut res resource.Resource, access u32) ? {
	security.mac_require(mut res, access)?
}
