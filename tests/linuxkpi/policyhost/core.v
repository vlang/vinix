// SPDX-License-Identifier: GPL-2.0-only
// Run the unchanged host fixture, then exercise the real native policy macros.
@[translated]
module policyhost

fn C.vinix_linuxkpi_i915_policy_native_selftest() i32
fn C.vinix_linuxkpi_host_original_main(i32, &&char) i32

@[export: 'main']
pub fn main_entry(argc i32, argv &&char) i32 {
	result := C.vinix_linuxkpi_host_original_main(argc, argv)
	if result != 0 { return result }
	return C.vinix_linuxkpi_i915_policy_native_selftest()
}
