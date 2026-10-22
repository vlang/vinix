// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import crypto.sha256
import os
import strings

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn local_offer_fixture(directory string) !string {
	runtime := 'Local runtime experiment. Source closure incomplete.\n'
	application := 'Local V probe.\n'
	source := 'Pinned source fragment, not a complete source distribution.\n'
	paths := ['runtime-LICENSE.txt', 'application-LICENSE.txt', 'wine-server.c']!
	contents := [runtime, application, source]!
	mut rows := []string{cap: 3}
	defer { unsafe { rows.free() } }
	for index, name in paths {
		path := directory + '/' + name
		os.write_file(path, contents[index])!
		digest := sha256.hexhash(contents[index])
		kind := if index == 2 { 'source' } else { 'notice' }
		url := if index == 2 { 'https://example.invalid/pinned/source.c' } else { 'local:publisher' }
		rows << '{"path":"' + name + '","kind":"' + kind + '","sha256":"' + digest + '","url":"' + url + '"}'
		unsafe { path.free(); digest.free() }
	}
	joined := rows.join(',')
	defer { unsafe { joined.free() } }
	text := '{"format":1,"status":"local-qualification-only","source_closure_complete":false,"runtime":"org.vinix.wine-runtime","version":"9.17-r1","architecture":"aarch64","reason":"Corresponding source is incomplete; local testing only.","artifacts":[' + joined + ']}'
	path := directory + '/source-offer.json'
	defer { unsafe { path.free() } }
	os.write_file(path, text)!
	return text
}

fn local_offer_refused(path string, runtime string, version string, architecture string) bool {
	mut offer := admit_local_source_offer(path, runtime, version, architecture) or { unsafe { err.free() }; return true }
	offer.close()
	return false
}

fn restore_local_offer_fixture(directory string) ! {
	text := local_offer_fixture(directory)!
	unsafe { text.free() }
}

fn check_local_refusal(directory string) {
	baseline := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert baseline >= 0
	C.close(baseline)
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 32 {
		assert local_offer_refused(directory, 'org.vinix.wine-runtime', '9.17-r1', 'aarch64')
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	check := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert check == baseline
	C.close(check)
}

fn test_local_source_inventory_identity_digests_links_and_cleanup() {
	pid := os.getpid().str()
	base := os.real_path(os.temp_dir())
	temporary := base + '/vinix-wine-source-' + pid
	defer { os.rmdir_all(temporary) or {}; unsafe { temporary.free(); base.free(); pid.free() } }
	os.mkdir(temporary)!
	directory := temporary + '/notices'
	defer { unsafe { directory.free() } }
	os.mkdir(directory)!
	text := local_offer_fixture(directory)!
	defer { unsafe { text.free() } }
	mut offer := admit_local_source_offer(directory, 'org.vinix.wine-runtime', '9.17-r1', 'aarch64')!
	assert offer.artifacts.len == 3 && !offer.source_closure_complete
	offer.close(); offer.close()
	baseline_fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert baseline_fd >= 0
	C.close(baseline_fd)
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 100 {
		mut repeated := admit_local_source_offer(directory, 'org.vinix.wine-runtime', '9.17-r1', 'aarch64')!
		repeated.close(); repeated.close()
		assert local_offer_refused(directory, 'org.vinix.other', '9.17-r1', 'aarch64')
		assert local_offer_refused(directory, 'org.vinix.wine-runtime', '9.17-r2', 'aarch64')
		assert local_offer_refused(directory, 'org.vinix.wine-runtime', '9.17-r1', 'x86_64')
	}
	$if track_heap ? {
		kept := C.vinix_heap_end()
		assert kept == 0, kept.str()
		println('LOCAL SOURCE ADMISSION 100 success and 300 identity refusal cycles retain zero tracked V bytes PASS')
	}
	final_fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert final_fd == baseline_fd
	C.close(final_fd)
	source := directory + '/wine-server.c'
	extra := directory + '/unlisted'
	manifest := directory + '/source-offer.json'
	linked := temporary + '/linked'
	defer { unsafe { source.free(); extra.free(); manifest.free(); linked.free() } }
	os.write_file(source, 'changed')!
	check_local_refusal(directory)
	restore_local_offer_fixture(directory)!
	os.write_file(extra, 'not inventoried')!
	check_local_refusal(directory)
	os.rm(extra)!
	os.symlink(directory, linked)!
	check_local_refusal(linked)
	os.rm(linked)!
	os.mv(source, extra)!
	os.symlink(extra, source)!
	check_local_refusal(directory)
	os.rm(source)!
	os.link(extra, source)!
	check_local_refusal(directory)
	os.rm(source)!
	os.rm(extra)!
	os.mkdir(source)!
	check_local_refusal(directory)
	os.rmdir(source)!
	restore_local_offer_fixture(directory)!
	os.write_file(source, '')!
	check_local_refusal(directory)
	restore_local_offer_fixture(directory)!
	oversized := 'x'.repeat(16 * 1024 * 1024 + 1)
	os.write_file(source, oversized)!
	unsafe { oversized.free() }
	check_local_refusal(directory)
	restore_local_offer_fixture(directory)!
	claimed := text.replace('local-qualification-only', 'redistributable').replace('"source_closure_complete":false', '"source_closure_complete":true')
	defer { unsafe { claimed.free() } }
	os.write_file(manifest, claimed)!
	check_local_refusal(directory)
	// Notice bytes cannot be disguised as source entries, and a manifest is
	// subject to the same ordinary-file and single-link policy as its evidence.
	missing_notice := text.replace('"path":"runtime-LICENSE.txt","kind":"notice"', '"path":"runtime-LICENSE.txt","kind":"source"').replace('"url":"local:publisher"', '"url":"https://example.invalid/notice"')
	defer { unsafe { missing_notice.free() } }
	os.write_file(manifest, missing_notice)!
	check_local_refusal(directory)
	os.mv(manifest, extra)!
	os.symlink(extra, manifest)!
	check_local_refusal(directory)
	os.rm(manifest)!
	os.link(extra, manifest)!
	check_local_refusal(directory)
	os.rm(manifest)!
	os.mv(extra, manifest)!
	os.write_file(manifest, '')!
	check_local_refusal(directory)
	os.write_file(manifest, text)!
	mut restored := admit_local_source_offer(directory, 'org.vinix.wine-runtime', '9.17-r1', 'aarch64')!
	restored.close()
	println('LOCAL SOURCE ADMISSION exact inventory, runtime/host identity, hashes, size bounds, linked/empty/non-file refusal and restoration PASS')
	println('LOCAL SOURCE ADMISSION every file/notice/manifest refusal repeated 32 times closes all descriptors PASS')
}

fn test_maximum_local_source_inventory_has_bounded_owned_storage() {
	pid := os.getpid().str()
	base := os.real_path(os.temp_dir())
	directory := base + '/vinix-wine-source-maximum-' + pid
	defer { os.rmdir_all(directory) or {}; unsafe { directory.free(); base.free(); pid.free() } }
	os.mkdir(directory)!
	text := local_offer_fixture(directory)!
	defer { unsafe { text.free() } }
	mut builder := strings.new_builder(64 * 1024)
	defer { unsafe { builder.free() } }
	builder.write_string(text[..text.len - 2])
	digest := local_source_digest('pinned evidence\n')
	defer { unsafe { digest.free() } }
	for index in 0 .. 253 {
		number := index.str()
		name := 'source-' + number + '.c'
		path := directory + '/' + name
		os.write_file(path, 'pinned evidence\n')!
		row := ',{"path":"' + name + '","kind":"source","sha256":"' + digest + '","url":"https://example.invalid/source"}'
		builder.write_string(row)
		unsafe { number.free(); name.free(); path.free(); row.free() }
	}
	builder.write_string(']}')
	maximum := builder.str()
	manifest := directory + '/source-offer.json'
	defer { unsafe { maximum.free(); manifest.free() } }
	os.write_file(manifest, maximum)!
	baseline := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert baseline >= 0
	C.close(baseline)
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 8 {
		mut offer := admit_local_source_offer(directory, 'org.vinix.wine-runtime', '9.17-r1', 'aarch64')!
		assert offer.artifacts.len == 256
		offer.close()
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, kept.str() }
	check := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert check == baseline
	C.close(check)
	println('LOCAL SOURCE ADMISSION all 256 artifacts use captured directory enumeration, retire digest scratch and close descriptors PASS')
}
