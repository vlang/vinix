// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_atof_preserves_floating_environment() {
	mut environment := [32]u64{}
	C.fegetenv(unsafe { voidptr(&environment[0]) })
	defer { C.fesetenv(unsafe { voidptr(&environment[0]) }) }
	for preset in [0, int(C.FE_INEXACT), int(C.FE_UNDERFLOW), int(C.FE_INVALID)] {
		C.feclearexcept(int(C.FE_ALL_EXCEPT))
		C.feraiseexcept(preset)
		expected := C.fetestexcept(int(C.FE_ALL_EXCEPT))
		for text in ['1e5000', '1e-5000', '0x1.8p-1074', '3.25', 'bad'] {
			darwin_atof(text.str)
			assert C.fetestexcept(int(C.FE_ALL_EXCEPT)) == expected
		}
	}
}

fn test_darwin_numeric_conversion_abi() {
	path := os.getenv('VINIX_IOS_NUMERIC_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
	}
}
