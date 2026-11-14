// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tools.packages.wineadapter

// Host diagnostic: compare the same payload/row count against independently
// compiled baseline and candidate adapters. Never use elapsed time as a flaky
// pass threshold; require complete links, idempotence and preserved private data.
fn run() ! {
	if os.args.len != 4 { return error('usage: SCALE FRESH_ROOT ROWS BYTES_PER_ASSET') }
	root := os.abs_path(os.args[1])
	rows := os.args[2].int()
	size := os.args[3].int()
	if os.exists(root) || os.is_link(root) || rows < 1 || rows > 900 || size < 1
		|| size > 64 * 1024 * 1024 || u64(rows) * u64(size) > 1024 * 1024 * 1024 {
		return error('fresh root and bounded nonempty inventory required')
	}
	store := root + '/store'
	old := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	selected := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(selected)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	payload := 'x'.repeat(size)
	defer { unsafe { payload.free() } }
	for index in 0 .. rows {
		name := '/' + index.str() + '.dll'
		os.write_file(old + name, 'old')!
		os.write_file(selected + name, payload)!
	}
	mut prefix := wineadapter.prepare_prefix(data, old)!
	defer { prefix.close() }
	os.write_file(data + '/sentinel', 'private data')!
	mut capture := wineadapter.capture_idle_binding_review(data, selected, store)!
	defer { capture.close() }
	if capture.review.bindings.len != rows || capture.review.prior_generation != 1 { return error('scale fixture admission differs') }
	started := time.sys_mono_now()
	capture.migrate_bindings()!
	elapsed := time.sys_mono_now() - started
	capture.migrate_bindings()!
	if capture.review.prior_generation != 0 || !capture.review.bindings.all(it.operation == .keep) { return error('scale migration incomplete') }
	for index in 0 .. rows {
		name := '/' + index.str() + '.dll'
		if os.readlink(data + '/wine/drive_c/windows/system32' + name)! != selected + name { return error('scale target differs') }
	}
	if os.read_file(data + '/sentinel')! != 'private data' || os.is_link(data + '/wine/.vinix-builtin-next')
		|| os.exists(data + '/wine/.vinix-builtin-next') { return error('scale private data or stage differs') }
	println('WINE MIGRATION SCALE PASS rows=' + rows.str() + ' payload_bytes=' + (u64(rows) * u64(size)).str() + ' migration_ns=' + elapsed.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
