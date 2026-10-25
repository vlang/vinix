module elf

import os

fn test_all_entropy_slots_keep_images_below_interpreter() {
	os.unsetenv('ELF_TEST_RANDOM_FAIL')
	for extent in [u64(0x100000), u64(28 * 1024 * 1024)] {
		for entropy := u64(0); entropy <= pie_span(extent) / image_alignment; entropy++ {
			os.setenv('ELF_TEST_RANDOM', entropy.str(), true)
			base := pie_load_base(extent)
			assert base >= 0x10000000
			assert base % 0x200000 == 0
			assert base + extent <= 0x40000000
		}
	}
}

fn test_entropy_failure_and_unmovable_images_keep_floor() {
	os.setenv('ELF_TEST_RANDOM_FAIL', '1', true)
	assert pie_load_base(0x100000) == 0x10000000
	os.unsetenv('ELF_TEST_RANDOM_FAIL')
	os.setenv('ELF_TEST_RANDOM', '1', true)
	room := interpreter_base - pie_base
	assert pie_load_base(room) == pie_base
	// Preserve the existing oversized-image fallback without claiming that
	// an image bigger than the available range ends below the interpreter.
	assert pie_load_base(room + 1) == pie_base
}
