// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_submit_lookup_order_guard_requires_early_probe_and_later_revalidation() {
	local := read(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	reference := 'pub(crate) fn submit( if data.flags != 0 || data.pad != 0 { return Err(EINVAL) };\n' +
		'.queues().get(data.queue_id.try_into()?).ok_or(ENOENT)?; let copy_commands = UserSlice::new(); SyncItem::parse_array();\n/// IOCTL: get_time:'
	check_submit_lookup_order_contract(local, reference)!
	probe := 'captured := f.capture_submission_queue(request.queue_id) or { return -2 }'
	for token in [probe, 'mut queue_resources := unsafe { captured.resources }', 'if queue.id != queue_id || queue.detached { continue }', 'defer { f.lock.release() }', 'resources.retain_file_reference()'] {
		if _ := check_submit_lookup_order_contract(local.replace(token, ''), reference) { assert false, token }
	}
	late := local.replace(probe, '').replace('defer { memory.free(stage_storage) }', 'defer { memory.free(stage_storage) }\n' + probe)
	if _ := check_submit_lookup_order_contract(late, reference) { assert false, 'late probe accepted' }
	if _ := check_submit_lookup_order_contract(local, reference.replace('ENOENT', 'EINVAL')) { assert false }
}
