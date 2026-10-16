// SPDX-License-Identifier: GPL-2.0-or-later
module applefixture

import macho

fn framework_resolve(library string, symbol string) !u64 {
	assert library.starts_with('/System/Library/Frameworks/') || library.starts_with('/usr/lib/')
	assert symbol.starts_with('_')
	return 0x900000000
}

fn test_framework_image_maps_and_binds_on_both_page_sizes() {
	for status in [u8(23), 24] {
		image := macho.parse(framework_image(status))!
		assert image.execution_issues().len == 0 && image.libraries.len == 5
		imports := image.imported_symbols()!
		for symbol in ['_NSHomeDirectory', '_NSTemporaryDirectory', '_NSSearchPathForDirectoriesInDomains',
			'_CFStringGetCString', '_CFDataCreate', '_SecItemAdd', '_SecItemCopyMatching', '_SecItemUpdate', '_SecItemDelete'] {
			assert imports.any(it.name == symbol), symbol
		}
		for page in [u64(4096), 16384] {
			layout := image.layout(page)!
			assert layout.entry == 0x800 && layout.size == 0x8000
			plan := image.plan_fixups(layout, 0x800000000, framework_resolve)!
			assert plan.len == imports.len && plan.len > 20
			for i, fixup in plan { assert fixup.offset == u64(0x4000 + i * 8) && fixup.value == 0x900000000 }
		}
	}
	println('APPLE-FRAMEWORK-IMAGE: ARM64 iOS execution layout, real framework imports, writable data fixups and 4K/16K mappings PASS')
}
