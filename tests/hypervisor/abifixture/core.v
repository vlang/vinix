// Original independent public ABI checks; native layouts remain compiler checks.
module abifixture

#include <abi-fixture-native-abi.h>

@[export: 'main']
pub fn run() i32 {
	return if usize(C.VINIX_HV_GET_API_VERSION) != 0x48560000
		|| usize(C.VINIX_HV_CREATE_VM) != 0x48560001
		|| usize(C.VINIX_HV_RUN) != 0x48560006 { i32(1) } else { i32(0) }
}
