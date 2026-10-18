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
	fn C.vinix_heap_size_at(u32) u64
}

fn builder_fixture() !string {
	path := os.real_path(os.temp_dir()) + '/vinix-native-builder-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64']! {
		root := path + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!; os.mkdir(root + '/licenses')!
		bytes := elffixture.image(architecture, 'static')
		for name in ['package-hello', 'counter', 'memo']! { os.write_file_array(root + '/bin/' + name, bytes)!; os.chmod(root + '/bin/' + name, 0o755)! }
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt']! { os.write_file(root + '/licenses/' + name, name)! }
	}
	return path
}

fn test_native_builder_complete_build_retention_probe() {
	fixture := builder_fixture()!; defer { os.rmdir_all(fixture) or {} }
	roots := fixture + '/roots'; target := fixture + '/lock'
	for attempt in 0 .. 3 {
		if os.exists(target) { os.rmdir_all(target)! }
		$if track_heap ? { C.vinix_heap_begin() }
		mut info := native_catalog('1.0.0', roots, target)!
		info.close(); info.close()
		$if track_heap ? {
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			println('NATIVE BUILDER attempt=' + attempt.str() + ' retained=' + kept.str() + ' allocations=' + count.str())
			mut sizes := map[u64]int{}
			for index in 0 .. count { size := C.vinix_heap_size_at(index); sizes[size]++ }
			println(sizes)
		}
		assert index_digest(os.read_file(target + '/catalog.json')!) == '249d6bfb150918c4586f86d68da6b6394800d150f7385c3654fadb7ab19a3fce'
	}
	fd := capture_prepared_root(roots + '/aarch64', 'probe')!; defer { C.close(fd) }
	$if track_heap ? { C.vinix_heap_begin() }
	profile_elf(fd, 'bin/counter', 'aarch64', 'static', true)!
	$if track_heap ? { println('ELF PROBE retained=' + C.vinix_heap_end().str() + ' allocations=' + C.vinix_heap_count().str()) }
}
