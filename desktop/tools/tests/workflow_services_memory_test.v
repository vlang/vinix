// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import desktop.workflowcore

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_shared_atomic_save_and_reads_release_temporary_buffers_and_identities() {
	root := os.real_path(os.temp_dir()) + '/vinix-atomic-memory-' + C.getpid().str()
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	path := root + '/document'
	data := 'complete document'.bytes()
	workflowcore.atomic_save(path, data, workflowcore.SaveOptions{create_only: true})!
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		id := workflowcore.identify(path)!
		workflowcore.atomic_save(path, data, workflowcore.SaveOptions{expected: id})!
		bytes := workflowcore.read_regular(path, 1000)!
		assert bytes == data
		unsafe { bytes.free() }
	}
	live := C.vinix_heap_end()
	assert live == 0, 'Shared save service retained ${live} bytes over 100 saves'
}
