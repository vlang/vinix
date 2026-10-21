// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module dependencyprobe

// Only the dependent DSO exports this JNI symbol; ART must search DT_NEEDED.
@[export: 'Java_org_vinix_bootstrap_Main_nativeDependency']
pub fn dependency_check(e voidptr, class voidptr) i32 {
	return 0x5744
}
