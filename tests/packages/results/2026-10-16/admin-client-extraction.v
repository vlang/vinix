module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); base := work + '/baseline/pkgadmin'
	os.mkdir_all(base)!
	if !os.is_file(work + '/original-main.v') {
		previous := os.exec(['git', 'show', '25a97b08a:tools/packages/main.v']); assert previous.exit_code == 0
		os.write_file(work + '/original-main.v', previous.output)!
		for name in ['protocol.v', 'request_reader.v', 'socket.c.v']! { os.cp('tools/packages/pkgadmin/' + name, base + '/' + name)! }
	}
	original := os.read_file(work + '/original-main.v')!
	start := original.index('fn admin_password()') or { panic('password') }
	end := original.index('fn admin_authorize()') or { panic('authorize') }
	mut client := original[start..end].replace('pkgadmin.', '')
	client = client.replace('fn admin_client(arguments []string)', 'fn run_with_socket(arguments []string, socket_path string)')
	client = client.replace('authclient.default_socket', 'socket_path').replace('admin_password()', 'read_password(0)').replace('fn read_password(0)', 'fn read_password(input int)')
	client = client.replace('admin_stream(', 'receive_output(')
	client = client.replace('C.isatty(0)', 'C.isatty(input)').replace('C.tcgetattr(0,', 'C.tcgetattr(input,').replace('C.tcsetattr(0,', 'C.tcsetattr(input,').replace('C.read(0,', 'C.read(input,')
	header := '// SPDX-License-Identifier: GPL-2.0-or-later\nmodule pkgadmin\nimport authclient\nimport authproto\nimport crypto.rand\nimport os\nimport tools.packages.pkgprotocol\n#include <termios.h>\nfn C.tcgetattr(int, voidptr) int\nfn C.tcsetattr(int, int, voidptr) int\nstruct C.termios { mut: c_lflag u32 }\n'
	os.write_file(base + '/client.c.v', header + client)!
	os.write_file(work + '/baseline/v.mod', "Module { name: 'admin-client-baseline' }\n")!
	os.write_file(work + '/baseline/client-extraction.v', os.read_file(@FILE)!)!
	println('Frozen administrator client from 25a97b08a; only module qualifiers, private function names, input fd and authentication socket are parameterized')
}
