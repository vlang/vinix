// Deterministic entropy for the unchanged production address picker.
module krandom

import os

pub fn fill(output voidptr, length u64, _blocking bool) bool {
	assert length == sizeof(u64)
	if os.getenv('ELF_TEST_RANDOM_FAIL') == '1' { return false }
	unsafe { *(&u64(output)) = os.getenv('ELF_TEST_RANDOM').u64() }
	return true
}
