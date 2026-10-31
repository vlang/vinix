// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Compile the production callback and error accessor, with only socket storage
// substituted. No lwIP packets or kernel scheduler are exercised by this test.
fn test_tcp_reset_errno_and_so_error() {
	root := os.dir(os.dir(os.dir(@FILE)))
	source := os.read_file(root + '/kernel/netcore/core.v')!
	work := os.join_path(os.temp_dir(), 'vinix-connect-reset-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or { panic(err) } }
	mut fixture := '@[translated]\nmodule main\npub enum Err_enum_t {'
	fixture += source.all_after('pub enum Err_enum_t {').all_before('\n}') + '\n}\n'
	fixture += 'pub type Err_t = i8\n'
	fixture += 'struct Vinix_socket {\nmut:\n tcp voidptr\n connecting i32\n connected i32\n peer_closed i32\n error i32\n}\n'
	for name in ['linux_error', 'tcp_failed', 'vinix_socket_error'] {
		anchor := 'pub fn ${name}('
		assert source.contains(anchor)
		fixture += anchor + source.all_after(anchor).all_before('\n}\n') + '\n}\n'
	}
	fixture += '
fn main() {
	// All lwIP errors, with and without an in-progress active open. Only RST
	// during connect may differ from the existing generic errno mapping.
	for connecting in [i32(0), i32(1)] {
		for code in -16 .. 1 {
			mut socket := Vinix_socket{connecting: connecting, connected: 1 - connecting, tcp: voidptr(1)}
			expected := if connecting == 1 && code == -14 { i32(111) } else { linux_error(Err_t(code)) }
			tcp_failed(&socket, Err_t(code))
			assert socket.error == expected
			assert socket.connecting == 0 && socket.connected == 0
			assert socket.peer_closed == 1 && socket.tcp == unsafe { nil }
			// Blocking connect peeks; SO_ERROR reads and clears the same errno.
			assert vinix_socket_error(&socket, 0) == expected
			assert vinix_socket_error(&socket, 0) == expected
			assert vinix_socket_error(&socket, 1) == expected
			assert vinix_socket_error(&socket, 0) == 0
		}
	}
	assert linux_error(Err_t(-14)) == 104
	mut connecting := Vinix_socket{connecting: 1}
	tcp_failed(&connecting, Err_t(Err_enum_t.err_rst))
	assert connecting.error == 111
	mut established := Vinix_socket{connected: 1}
	tcp_failed(&established, Err_t(Err_enum_t.err_rst))
	assert established.error == 104
	tcp_failed(unsafe { nil }, Err_t(Err_enum_t.err_rst))
	assert vinix_socket_error(unsafe { nil }, 1) == 88
}
'
	path := work + '/reset.v'
	os.write_file(path, fixture)!
	result :=
		os.execute('${os.quoted_path(@VEXE)} -cc clang -o ${os.quoted_path(work + '/reset')} run ${os.quoted_path(path)}')
	assert result.exit_code == 0, result.output
}
