// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn run(args []string) !string {
	mut p := os.new_process('git')
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { return error(output) }
	return output
}

fn main() {
	assert os.args.len == 3, 'usage: reference PINNED_LINUX FRESH_EXTERNAL_STATE'
	root := os.abs_path(os.args[1])
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(os.getwd() + '/')
	assert run(['-C', root, 'rev-parse', 'HEAD'])!.trim_space() == 'bed544bdf93a496ebf70ba180923bab12b6e01cf'
	os.mkdir_all(state)!
	mut paths := ['drivers/gpu/drm/asahi/file.rs']
	for path in os.walk_ext(root + '/drivers/gpu/drm/asahi/queue', '.rs') {
		paths << path[root.len + 1..]
	}
	paths.sort()
	for path in paths {
		bytes := os.read_bytes(root + '/' + path)!
		assert sha256.sum(bytes) == sha256.sum(run(['-C', root, 'show', 'HEAD:' + path])!.bytes())
		os.mkdir_all(os.dir(state + '/' + path))!
		os.write_file_array(state + '/' + path, bytes)!
		println(path + ' sha256 ' + sha256.sum(bytes).hex())
		if path != 'drivers/gpu/drm/asahi/queue/mod.rs' {
			assert !bytes.bytestr().contains('fn reserve_render_scs(')
		}
	}
	file := os.read_file(state + '/drivers/gpu/drm/asahi/file.rs')!
	start := file.index('    pub(crate) fn queue_create(') or { panic('queue_create') }
	end := file.index_after('    /// IOCTL: queue_destroy:', start) or { panic('queue_destroy') }
	queue := file[start..end]
	mut position := 0
	for token in ['if data.flags != 0',
		'data.priority == uapi::drm_asahi_priority_DRM_ASAHI_PRIORITY_REALTIME', 'vms_xa.lock()',
		'guard.get(data.vm_id.try_into()?).ok_or(ENOENT)?', 'reg_data.gpu.new_queue(',
		'queue.reserve_render_scs(data.render_scs_layout)?', 'data.queue_id =', 'resv.fill('] {
		position = (queue.index_after(token, position) or { panic('missing/out-of-order ' + token) }) + token.len
	}
	default_queue := os.read_file(state + '/drivers/gpu/drm/asahi/queue/mod.rs')!
	assert default_queue.contains('fn reserve_render_scs(&mut self, layouts: [u64; 2]) -> Result {\n        if layouts != [0; 2] { return Err(EINVAL); }\n        Ok(())')
	println('Pinned G13 Rust source order: validate header/priority, resolve VM, construct queue, reject nonzero render SCS, publish name. Default trait has no G13 queue override. Source comparison only; Rust not executed.')
}
