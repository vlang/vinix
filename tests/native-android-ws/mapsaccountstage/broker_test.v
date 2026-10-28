// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2
import os

fn broker_test_write(root string, path string, content string, mut files map[string]string) ! {
	os.mkdir_all(os.dir(root + '/' + path))!
	os.write_file(root + '/' + path, content)!
	files[path] = digest(root + '/' + path)!
}
fn broker_test_command(root string, label string, argv []string, mut files map[string]string) ! {
	broker_test_write(root, 'commands/' + label + '.json', json2.encode({'argv': json2.Any(argv), 'exit_code': json2.Any(0)}), mut files)!
}
fn broker_test_inputs(root string) !Bundle {
	mut files := map[string]string{}
	runtime := 'closure/broker/frozen/vlib/builtin/segfault_handler_nix.c'
	for path in ['generated/broker.c', 'generated/broker.o', 'generated/broker-runtime.o', runtime, 'cross/crti.o', 'cross/crtbegin.o', 'cross/crtn.o'] {
		broker_test_write(root, path, path, mut files)!
	}
	for pair in [['broker', root + '/generated/broker.c'], ['broker-runtime', root + '/' + runtime]] {
		mut compile := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-Werror=implicit-function-declaration', '-Werror=int-conversion']
		compile << ['-c', pair[1], '-o', root + '/generated/' + pair[0] + '.o']
		broker_test_command(root, 'compile-' + pair[0], compile, mut files)!
		broker_test_command(root, pair[0] + '-headers', [cross, '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-M', '-MT', pair[0], pair[1]], mut files)!
		broker_test_write(root, 'generated/' + pair[0] + '-headers.json', json2.encode({pair[1]: files[pair[1][root.len + 1..]]!}), mut files)!
		broker_test_write(root, 'commands/' + pair[0] + '-headers.log', pair[0] + ': ' + pair[1] + '\n', mut files)!
	}
	objects := [root + '/generated/broker.o', root + '/generated/broker-runtime.o']
	mut link := [cross, '-v', '-no-pie', '-pthread', '-Wl,-t', '-static']
	link << objects
	link << ['-ldl', '-lm', '-o', root + '/bin/native-account-broker']
	broker_test_command(root, 'build-broker', link, mut files)!
	mut consumed := map[string]string{}
	for path in ['generated/broker.o', 'generated/broker-runtime.o', 'cross/crti.o', 'cross/crtbegin.o', 'cross/crtn.o'] { consumed[root + '/' + path] = files[path]! }
	broker_test_write(root, 'commands/build-broker.log', consumed.keys().join('\n') + '\n', mut files)!
	broker_test_write(root, 'generated/broker-link-inputs.json', json2.encode(consumed), mut files)!
	broker_test_write(root, 'cross-inputs.json', '{}', mut files)!
	return Bundle{root: root, files: files}
}

fn test_broker_rejects_missing_or_unconsumed_retained_build_inputs() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-broker-inputs-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	valid := broker_test_inputs(root)!
	verify_broker_build_inputs(valid)!
	for path in ['generated/broker.c', 'generated/broker.o', 'generated/broker-runtime.o',
		'generated/broker-headers.json', 'generated/broker-runtime-headers.json', 'generated/broker-link-inputs.json',
		'commands/broker-headers.log', 'commands/broker-runtime-headers.log', 'commands/build-broker.log', 'cross-inputs.json'] {
		mut missing := valid.files.clone()
		missing.delete(path)
		if _ := verify_broker_build_inputs(Bundle{...valid, files: missing}) { assert false, 'missing retained broker build input accepted: ' + path }
	}
	for path in ['generated/broker-headers.json', 'generated/broker-runtime-headers.json', 'generated/broker-link-inputs.json'] {
		original := os.read_file(root + '/' + path)!
		mut files := valid.files.clone()
		broker_test_write(root, path, '{}', mut files)!
		if _ := verify_broker_build_inputs(Bundle{...valid, files: files}) { assert false, 'empty broker consumed inventory accepted: ' + path }
		os.write_file(root + '/' + path, original)!
	}
	mut files := valid.files.clone()
	broker_test_write(root, 'commands/build-broker.log', '\n', mut files)!
	if _ := verify_broker_build_inputs(Bundle{...valid, files: files}) { assert false, 'empty broker link trace accepted' }
}

fn test_broker_requires_static_executable_with_load_segment() ! {
	mut bytes := []u8{len: 120}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { bytes[index] = value }
	bytes[16] = 2
	bytes[18] = 183
	bytes[20] = 1
	bytes[32] = 64
	bytes[52] = 64
	bytes[54] = 56
	bytes[56] = 1
	bytes[64] = 1
	bytes[96] = 120
	bytes[104] = 120
	verify_broker_static_elf(bytes)!
	mut dynamic := bytes.clone()
	dynamic[16] = 3
	if _ := verify_broker_static_elf(dynamic) { assert false, 'ET_DYN broker accepted' }
	mut no_load := bytes.clone()
	no_load[64] = 0
	if _ := verify_broker_static_elf(no_load) { assert false, 'broker without PT_LOAD accepted' }
}
