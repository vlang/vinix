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
	paths := ['drivers/gpu/drm/asahi/file.rs', 'include/uapi/drm/asahi_drm.h']
	for path in paths {
		bytes := os.read_bytes(root + '/' + path)!
		assert sha256.sum(bytes) == sha256.sum(run(['-C', root, 'show', 'HEAD:' + path])!.bytes())
		os.mkdir_all(os.dir(state + '/' + path))!
		os.write_file_array(state + '/' + path, bytes)!
		println(path + ' sha256 ' + sha256.sum(bytes).hex())
	}
	file := os.read_file(state + '/drivers/gpu/drm/asahi/file.rs')!
	start := file.index('    fn parse_array(') or { panic('parse_array') }
	end := file.index_after('#[derive(Clone)]', start) or { panic('parse_array end') }
	parser := file[start..end]
	mut position := 0
	for token in ['in_count.checked_add(out_count).ok_or(EOVERFLOW)?',
		'STRIDE.checked_mul(count as usize).ok_or(EOVERFLOW)?',
		'KVec::with_capacity(count as usize, GFP_KERNEL)?', 'UserSlice::new(', 'for i in 0..count',
		'reader.read_raw(', 'Self::parse_one(file, sync, i >= in_count'] {
		position = (parser.index_after(token, position) or { panic('missing/out-of-order ' + token) }) + token.len
	}
	assert !parser.contains('count > 64') && !parser.contains('max_syncs')
	println('Pinned modern sync parser: checked u32 count sum and byte product, fallible KVec capacity, one read per 16-byte record and wire-order parsing; no 64-record bound. Source comparison only; Rust not executed.')
}
