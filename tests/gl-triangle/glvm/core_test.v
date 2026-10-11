// SPDX-License-Identifier: GPL-2.0-or-later
module glvm

fn test_readelf_dependency_order_and_exact_names() {
	assert needed_libraries('unrelated [not a dependency]\nShared library: [libEGL.so.1]\nShared library: [libc.musl-aarch64.so.1]\nShared library: []\n') == [
		'libEGL.so.1',
		'libc.musl-aarch64.so.1',
	]
	assert needed_libraries('Shared library: [unterminated') == []string{}
}
