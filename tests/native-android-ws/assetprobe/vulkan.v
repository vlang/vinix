// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

struct VulkanInstanceInfo {
	s_type          i32
	p_next          voidptr
	flags           u32
	application     voidptr
	layer_count     u32
	layers          &&char
	extension_count u32
	extensions      &&char
}

fn C.vkEnumerateInstanceVersion(&u32) i32
fn C.vkEnumerateInstanceLayerProperties(&u32, voidptr) i32
fn C.vkEnumerateInstanceExtensionProperties(&char, &u32, voidptr) i32
fn C.vkGetInstanceProcAddr(voidptr, &char) voidptr
fn C.vkCreateInstance(&VulkanInstanceInfo, voidptr, &voidptr) i32

// These are ordinary ELF imports, resolved through libfixture.so's Android
// DT_NEEDED entry. The APK contains neither a loader nor an ICD.
@[export: 'Java_org_vinix_bootstrap_Main_nativeVulkan']
pub fn vulkan_check(e voidptr, class voidptr) u8 {
	unsafe {
		mut version := u32(0)
		mut layers := u32(99)
		mut extensions := u32(0)
		if C.vkEnumerateInstanceVersion(&version) != 0
			|| version != (u32(1) << 22 | u32(3) << 12 | 261)
			|| C.vkEnumerateInstanceLayerProperties(&layers, nil) != 0 || layers != 0
			|| C.vkEnumerateInstanceExtensionProperties(nil, &extensions, nil) != 0
			|| C.vkGetInstanceProcAddr(nil, c'vkCreateInstance') == nil
			|| C.vkGetInstanceProcAddr(nil, c'vkVinixNonexistentProcedure') != nil {
			C.puts(c'VULKAN-PROBE global-entrypoints')
			return 0
		}
		info := VulkanInstanceInfo{ s_type: 1 }
		mut instance := voidptr(nil)
		if C.vkCreateInstance(&info, nil, &instance) != -9 || instance != nil {
			C.puts(c'VULKAN-PROBE expected-incompatible-driver')
			return 0
		}
		C.puts(c'BOOTSTRAP-VULKAN-PASS needed-imports version procedures no-icd-rejected')
		return 1
	}
}
