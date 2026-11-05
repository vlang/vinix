// SPDX-License-Identifier: GPL-2.0-or-later
// V generation plus entry-renaming glue; no legacy C byte is edited.
module perfproducer

import crypto.sha256
import json2
import os
import hwhost

pub const legacy_sha256 = '2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771'

pub fn generate(compiler string, root string, directory string, arch string) !string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported producer architecture') }
	legacy := os.read_file(root + '/tests/desktop-perf/measure.c')!
	if sha256.hexhash(legacy) != legacy_sha256 { return error('legacy operation-probe source differs') }
	for name in ['measure-v.c', 'measure-legacy.c', 'measure-combined.c', 'measure-v.argv.json', 'measure-v.log'] {
		if os.exists(directory + '/' + name) || os.is_link(directory + '/' + name) {
			return error('producer output must be fresh')
		}
	}
	vfile := directory + '/measure-v.c'
	// The guest declares the native i32 handler field; os's V-int handler
	// metadata would insert a callback adapter with a different native ABI.
	argv := [compiler, '-backend', 'c', '-prod', '-nocache', '-enable-globals', '-os', 'linux',
		'-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree',
		'-exclude', '@vlib/os/os_structs_sigaction_default.c.v',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib|@vmodules|' + root + '/tests/desktop-perf',
		'-o', vfile, root + '/tests/desktop-perf/measure-v']
	os.write_file(directory + '/measure-v.argv.json', json2.encode(argv) + '\n')!
	hwhost.run_tool(argv, {}, directory + '/measure-v.log', 300)!
	copy := directory + '/measure-legacy.c'
	os.write_file(copy, legacy)!
	if sha256.hexhash(os.read_file(copy)!) != legacy_sha256 { return error('legacy probe copy differs') }
	if copy.contains_any('"\\\r\n') { return error('unsupported generated include path') }
	combined := directory + '/measure-combined.c'
	// Only preprocessor entry renaming: probe bodies and the old non-heap modes
	// remain unchanged in the same translation unit as the V observer.
	os.write_file(combined, '#define main vinix_perf_legacy_main\n#include "' + copy + '"\n#undef main\n'
		+ os.read_file(vfile)!)!
	return combined
}
