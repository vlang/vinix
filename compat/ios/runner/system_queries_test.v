// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_system_protocol_database() {
	path := os.join_path(os.temp_dir(), 'vinix-ios-protocols-${os.getpid()}')
	defer { os.rm(path) or {} }
	os.write_file(path, '# actual database records\nmalformed\nbad nope BAD\noverflow 2147483648 OVERFLOW\n' +
		'  custom\t123\tFIRST second # ignored comment\nnoaliases 124\n' +
		'large 125 ' + 'x'.repeat(8192) + ' LAST\n')!
	mut protocol := DarwinProtocol{}
	defer { system_protocol_clear(mut protocol) }
	assert system_protocol_file(path.str, c'second', &protocol) == 0
	assert protocol.number == 123
	assert C.strcmp(protocol.name, c'custom') == 0
	assert unsafe { C.strcmp(protocol.aliases[0], c'FIRST') } == 0
	assert unsafe { C.strcmp(protocol.aliases[1], c'second') } == 0
	assert unsafe { protocol.aliases[2] == nil }
	system_protocol_clear(mut protocol)
	assert system_protocol_file(path.str, c'LAST', &protocol) == 0
	assert protocol.number == 125
	assert unsafe { C.strlen(protocol.aliases[0]) } == 8192
	system_protocol_clear(mut protocol)
	assert system_protocol_file(path.str, c'noaliases', &protocol) == 0
	assert unsafe { protocol.aliases[0] == nil }
	system_protocol_clear(mut protocol)
	for name in [c'overflow', c'bad', c'ignored', c'missing', c'Second'] {
		assert system_protocol_file(path.str, name, &protocol) == 1
		assert protocol.name == unsafe { nil }
	}
	os.rm(path)!
	assert system_protocol_file(path.str, c'custom', &protocol) == -1
	assert unsafe { *C.ios_errno_address() } == C.ENOENT
}

fn test_system_query_account_buffer_growth() {
	system_data = &SystemData{}
	system_queries_start()!
	defer {
		system_queries_stop()
		unsafe { free(system_data) }
		system_data = unsafe { nil }
	}
	mut storage := system_query_storage()
	assert storage != unsafe { nil }
	storage.account_capacity = 16
	storage.account_buffer = C.malloc(16)
	assert storage.account_buffer != unsafe { nil }
	darwin_set_errno(177)
	account := darwin_getpwuid(C.getuid())
	assert account != unsafe { nil }
	assert account.uid == C.getuid()
	assert storage.account_capacity > 16
	assert usize(account.name) >= usize(storage.account_buffer)
	assert usize(account.name) < usize(storage.account_buffer) + storage.account_capacity
	assert unsafe { *C.ios_errno_address() } == 177
}

fn test_darwin_system_queries_macho() {
	path := os.getenv('VINIX_IOS_SYSTEM_QUERIES_FIXTURE')
	if path == '' { return }
	assert sizeof(DarwinPasswd) == 72
	assert sizeof(DarwinProtocol) == 24
	assert sizeof(DarwinRusage) == 144
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
		assert system_data == unsafe { nil }
	}
}
