module elf

import os

fn test_manually_invoked_loader_leaves_fixed_executable_free() {
	// Maps334 placed musl at 0x400000. Its target ET_EXEC occupies
	// [0x400000, 0x441000), so musl cannot map it at its fixed address.
	os.setenv('ELF_TEST_RANDOM', '1', true)
	os.unsetenv('ELF_TEST_RANDOM_FAIL')
	loader_base := pie_load_base(0x100000)
	assert loader_base >= 0x441000 || loader_base + 0x100000 <= 0x400000,
		'PIE_FIXED_EXEC_COLLISION'
}
