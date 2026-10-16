// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn native_owned_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-native-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64']! {
		root := work + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!
		os.mkdir_all(root + '/licenses')!
		bytes := elffixture.image(architecture, 'static')
		for name in ['package-hello', 'counter', 'memo']! {
			os.write_file_array(root + '/bin/' + name, bytes)!
			os.chmod(root + '/bin/' + name, 0o755)!
		}
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt']! { os.write_file(root + '/licenses/' + name, name)! }
	}
	return work
}

fn test_native_owned_baseline() {
	if '--native-owned-baseline' !in os.args { return }
	work := native_owned_fixture()!
	defer { os.rmdir_all(work) or {} }
	roots := work + '/roots'; target := work + '/lock'
	$if track_heap ? { C.vinix_heap_begin() }
	info := native_catalog('1.0.0', roots, target)!
	// The original reply borrowed version/architecture strings, but owned the
	// destination, digest and architecture buffer. Retire only those owners.
	unsafe { info.directory.free(); info.catalog.free(); info.catalog_sha256.free(); (&array(&info.architectures)).free() }
	$if track_heap ? {
		kept := C.vinix_heap_end(); count := C.vinix_heap_count()
		println('NATIVE OWNERSHIP baseline whole-build retained=' + kept.str() + ' allocations=' + count.str())
	}
	text := os.read_file(target + '/catalog.json')!
	println('NATIVE OWNERSHIP baseline canonical=' + index_digest(text))
	if output := os.getenv_opt('VINIX_NATIVE_OWNERSHIP_GOLDEN') { os.write_file(output, text)! }
}
