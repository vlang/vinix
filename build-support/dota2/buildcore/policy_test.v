// SPDX-License-Identifier: GPL-2.0-or-later
module buildcore

import hosttest
import json2
import os

fn test_pin_rejections_keep_order_and_types() {
	valid := Value({
		'format': Value(Number{'2.0', false, ''})
		'debian_version': Value('pinned')
		'mirror': Value('https://example.invalid')
		'source': Value({'filename': Value('source'), 'sha256': Value('x'.repeat(64))})
		'debian_diff': Value({'filename': Value('diff'), 'sha256': Value('\xed\xa0\x80'.repeat(64))})
		'patches': Value({'patch': Value('x'.repeat(64))})
		'packages': Value([]Value{})
	})
	validate_mesa(valid, 'pin') or { assert false, err.msg() }
	validate_mesa(Value([]Value{}), 'pin') or {
		assert err is PolicyError
		assert err.kind == 'AttributeError'
		assert err.msg() == "'list' object has no attribute 'get'"
	}
	validate_glibc(Value({'package': Value('other'), 'size': Value(json2.Null{})}), 'pin') or {
		assert err is PolicyError
		assert err.kind == 'SystemExit'
		assert err.msg() == 'invalid pinned amd64 libc6 package: pin'
	}
}

fn test_complete_family_and_aliases_are_measured() {
	root := hosttest.work_dir('', 'vinix-dota-policy-') or { panic(err) }
	defer { hosttest.remove_work_dir(root) or { panic(err) } }
	names := ['ld-linux-x86-64.so.2', 'libc.so.6', 'libm.so.6', 'libresolv.so.2', 'libpthread.so.0', 'libdl.so.2']
	for directory in ['usr/lib/x86_64-linux-gnu', 'lib/x86_64-linux-gnu', 'lib64'] {
		os.mkdir_all(root + '/' + directory) or { panic(err) }
	}
	mut files := map[string]Value{}
	mut aliases := map[string]Value{}
	for name in names {
		relative := 'usr/lib/x86_64-linux-gnu/' + name
		os.write_file(root + '/' + relative, 'native family ' + name) or { panic(err) }
		os.chmod(root + '/' + relative, 0o755) or { panic(err) }
		files[relative] = Value({'sha256': Value(hosttest.sha(root + '/' + relative) or { panic(err) }), 'mode': Value(Number{'493', true, ''})})
		if name != names[0] {
			legacy := 'lib/x86_64-linux-gnu/' + name
			target := '../../usr/lib/x86_64-linux-gnu/' + name
			os.symlink(target, root + '/' + legacy) or { panic(err) }
			aliases[legacy] = Value(target)
		}
	}
	loader := 'lib64/ld-linux-x86-64.so.2'
	os.symlink('../usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2', root + '/' + loader) or { panic(err) }
	aliases[loader] = Value('../usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2')
	pin := Value({'version': Value('fixed')})
	marker := Value({'package': pin, 'alias_policy': Value('policy'), 'files': Value(files), 'aliases': Value(aliases)})
	assert glibc_valid(root, marker, pin, 'policy', names)
	os.chmod(root + '/usr/lib/x86_64-linux-gnu/libc.so.6', 0o644) or { panic(err) }
	assert !glibc_valid(root, marker, pin, 'policy', names)
	os.chmod(root + '/usr/lib/x86_64-linux-gnu/libc.so.6', 0o755) or { panic(err) }
	assert glibc_valid(root, marker, pin, 'policy', names)
	os.rm(root + '/' + loader) or { panic(err) }
	os.symlink('/tmp', root + '/' + loader) or { panic(err) }
	assert !glibc_valid(root, marker, pin, 'policy', names)
}

fn test_greedy_dependencies_and_table_bounds() {
	assert needed('(NEEDED)[one][two]\n(NEEDED)[long\nname]') == ['two', 'long\nname']
	mut bytes := []u8{len: 120}
	copy(mut bytes[..6], [u8(0x7f), `E`, `L`, `F`, 2, 1])
	bytes[16] = 2
	bytes[18] = 183
	bytes[32] = 64
	bytes[54] = 56
	bytes[56] = 1
	assert static_translator(bytes, '')
	bytes[64] = 3
	assert !static_translator(bytes, '')
	bytes[64] = 1
	for i in 32 .. 40 { bytes[i] = 255 }
	assert !static_translator(bytes, '')
}
