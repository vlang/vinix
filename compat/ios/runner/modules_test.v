// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_bundle_loader_and_tls_lifecycle() {
	path := os.getenv('VINIX_IOS_MODULES_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	assert audit_imports(image, path)! == 0
	assert module_runtime == unsafe { nil } && ios_runtime.live == 0
	// Run twice in one process: mappings, selectors, per-image TLS and the
	// library-owned classes/destructor state must be recreated after teardown.
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert module_runtime == unsafe { nil }
		assert image_runtime == unsafe { nil }
		assert ios_runtime.live == 0
	}
}
