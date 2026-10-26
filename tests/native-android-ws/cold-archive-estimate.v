// SPDX-License-Identifier: GPL-2.0-or-later
// Count a complete compressed archive stream without storing it or changing evidence.
module main

import crypto.sha256
import json2
import os
import time

#include <fcntl.h>
struct C.log2phys {
mut:
	l2p_flags u32
	l2p_contigbytes i64
	l2p_devoffset i64
}
fn C.fcntl(int, int, ...voidptr) int

fn extent_probe(path string) !map[string]json2.Any {
	mut file := os.open(path)!
	defer { file.close() }
	mut mapping := C.log2phys{l2p_contigbytes: i64(os.file_size(path))}
	result := C.fcntl(file.fd, C.F_LOG2PHYS_EXT, unsafe { &mapping })
	return {
		'path': json2.Any(path)
		'fcntl_result': json2.Any(result)
		'errno': json2.Any(if result == 0 { 0 } else { C.errno })
		'first_extent_bytes': json2.Any(mapping.l2p_contigbytes)
		'first_device_offset': json2.Any(mapping.l2p_devoffset)
		'warning': json2.Any('A first extent is not a unique-allocation measurement; clone references elsewhere may share it.')
	}
}

fn main() {
	assert os.args.len == 4, 'cold-archive-estimate BUNDLE MANIFEST_SHA256 NEW_RECEIPT'
	root := os.args[1]
	pin := os.args[2]
	output := os.args[3]
	assert os.real_path(root) == root && os.is_dir(root) && !os.is_link(root)
	assert !os.exists(output) && !os.is_link(output)
	assert sha256.sum(os.read_bytes(root + '/sha256.json')!).hex() == pin
	started := time.utc().str()
	argv := ['-czf', '-', '--options', 'gzip:compression-level=1', '-C', os.dir(root), os.base(root)]
	mut process := os.new_process('/usr/bin/tar')
	process.set_args(argv)
	process.set_redirect_stdio()
	process.run()
	mut bytes := u64(0)
	mut digest := sha256.new()
	mut stderr := ''
	for {
		chunk := process.stdout_read()
		if chunk.len > 0 {
			bytes += u64(chunk.len)
			digest.write(chunk.bytes())!
		}
		stderr += process.stderr_read()
		if chunk.len == 0 {
			if !process.is_alive() { break }
			time.sleep(time.millisecond)
		}
	}
	process.wait()
	stderr += process.stderr_slurp()
	code := process.code
	process.close()
	assert sha256.sum(os.read_bytes(root + '/sha256.json')!).hex() == pin
	mut extents := []json2.Any{}
	for relative in ['prelaunch/vm-baseline/boot.img', 'prelaunch/vm-fixed/boot.img', 'completed/vm-baseline/boot.img', 'completed/vm-fixed/boot.img'] {
		path := root + '/' + relative
		if os.exists(path) { extents << json2.Any(extent_probe(path)!) }
	}
	du := os.exec(['/usr/bin/du', '-sk', root])
	df := os.exec(['/bin/df', '-k', root])
	assert du.exit_code == 0 && df.exit_code == 0
	mut all_argv := ['/usr/bin/tar']
	all_argv << argv
	receipt := {
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'root': json2.Any(root)
		'manifest_sha256': json2.Any(pin)
		'source_sha256': json2.Any(sha256.sum(os.read_bytes(os.real_path(@FILE))!).hex())
		'binary_sha256': json2.Any(sha256.sum(os.read_bytes(os.executable())!).hex())
		'archive_reader_sha256': json2.Any(sha256.sum(os.read_bytes('/usr/bin/tar')!).hex())
		'argv': json2.Any(all_argv)
		'exit_code': json2.Any(code)
		'stderr': json2.Any(stderr)
		'compressed_stream_bytes': json2.Any(bytes)
		'discarded_stream_sha256': json2.Any(digest.sum([]u8{}).hex())
		'du_kib': json2.Any(du.output)
		'df_kib': json2.Any(df.output)
		'first_extent_probes': json2.Any(extents)
		'qualification': json2.Any('Read-only size estimate; no archive retained, no restore or deletion performed, no unique physical recovery established.')
	}
	os.write_file(output, json2.encode(receipt, prettify: true) + '\n')!
	assert code == 0, 'archive stream generation failed; receipt retained'
	println('COLD-ARCHIVE-ESTIMATE bytes=' + bytes.str() + ' receipt=' + output)
}
