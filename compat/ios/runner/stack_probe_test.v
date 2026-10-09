// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

#include "@VMODROOT/abi/stack-probe-test.h"
fn C.ios_stack_probe_guard_test(int) int

fn test_stack_probe_respects_native_memory_guards() {
	$if ios_stack_probe_test ? {
		fault := if os.getenv('VINIX_IOS_STACK_PROBE_FAULT') == '1' { 1 } else { 0 }
		assert C.ios_stack_probe_guard_test(fault) == 0
		assert fault == 0 // The faulting child must die before returning here.
	}
}

fn test_native_compiler_stack_probes_and_argument_preservation() {
	path := os.getenv('VINIX_IOS_STACK_PROBE_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	symbols := image.imported_symbols()!
	defer {
		for symbol in symbols { unsafe { symbol.name.free() } }
		unsafe { symbols.free() }
	}
	assert symbols.any(it.name == '___chkstk_darwin')
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
	}
}
