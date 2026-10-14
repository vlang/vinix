// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.appsdk

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn main() {
	sets := [ []string{}, ['files'], ['audio', 'display', 'files', 'network', 'process'], ['files', 'files'],
		['root'], ['audio', 'display', 'files', 'network', 'process', 'files'] ]
	C.vinix_heap_begin()
	for _ in 0 .. 1000 {
		for index, values in sets { assert appsdk.valid_permissions(values) == (index < 3) }
	}
	assert C.vinix_heap_end() == 0
	println('SDK permission admission: 1000 empty/valid/full/repeated/unknown/oversized cycles retain zero tracked bytes')
	key := '0123456789abcdef'.repeat(4)
	defer { unsafe { key.free() } }
	fields := appsdk.Fields{ sdk: '1', id: 'org.example.app', version: '1.2.3', architecture: 'aarch64', kind: 'linux',
		generation: '42', repository: 'publisher', public_key: key, sequence: '7',
		app_directory: '/var/lib/vinix-packages/generations/42/apps/org.example.app', data_directory: '/home/user/a space; $literal',
		runtime_id: 'runtime', runtime_version: '2.0.0', runtime_directory: '/var/lib/vinix-packages/generations/42/apps/runtime', permissions: 'network files' }
	mut initial := appsdk.decode(fields)!
	mut environment := initial.environment()!
	for value in environment {
		separator := value.index('=') or { panic('missing equals') }
		name := value[..separator]
		contents := value[separator + 1..]
		assert os.setenv(name, contents, true) == 0
		unsafe { name.free(); contents.free() }
	}
	assert os.setenv('HOME', fields.data_directory, true) == 0
	assert os.setenv('TMPDIR', fields.data_directory + '/tmp', true) == 0
	appsdk.free_values(mut environment); initial.close()
	invalid_fields := [appsdk.Fields{ ...fields, generation: '0' }, appsdk.Fields{ ...fields, permissions: 'files files' },
		appsdk.Fields{ ...fields, runtime_directory: '/outside' }]
	defer { unsafe { (&array(&invalid_fields)).free() } }
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 100 {
			mut decoded := appsdk.decode(fields)!
			mut values := decoded.environment()!
			assert values.len == 15 && 'VINIX_APP_PERMISSIONS=files network' in values
			appsdk.free_values(mut values)
			decoded.close(); decoded.close()
			mut loaded := appsdk.load()!
			assert loaded.id == fields.id && loaded.runtime_version == '2.0.0'
			loaded.close()
			assert os.setenv('HOME', '/wrong-context-home', true) == 0
			mut mismatch := false
			appsdk.load() or { mismatch = true; unsafe { err.free() } }
			assert mismatch
			assert os.setenv('HOME', fields.data_directory, true) == 0
			for invalid in invalid_fields {
				mut refused := false
				appsdk.decode(invalid) or { refused = true; unsafe { err.free() } }
				assert refused
			}
		}
	}
	kept := C.vinix_heap_end()
	assert kept == 0, 'application context retained ${kept} bytes'
	println('Application SDK context: repeated decode/load/encode/refusal/close retain zero tracked bytes')
}
