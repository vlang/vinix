// SPDX-License-Identifier: GPL-2.0-or-later
// Compile unchanged production sources in an isolated host module.
module main

import os

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..', '..'))
	scratch := os.getenv_opt('TMPDIR') or { os.temp_dir() }
	work := os.join_path(scratch, 'vinix-smb2-protocol-${os.getpid()}')
	os.mkdir_all(work + '/smb2')!
	os.mkdir_all(work + '/krandom')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'smb2_host_checks' }")!
	for name in ['wire.v', 'crypto.v', 'ntlm.v', 'completion.v', 'options.v', 'client.v'] {
		os.cp(root + '/kernel/fs/smb2/' + name, work + '/smb2/' + name)!
	}
	// Only the kernel dependency is substituted; all SMB2 sources are exact copies.
	os.cp(root + '/tests/smb2/protocol/sha256.fixture', work + '/krandom/sha256.v')!
	os.cp(root + '/tests/smb2/protocol/production_test.v', work + '/smb2/production_test.v')!
	compiler := os.getenv_opt('V') or { @VEXE }
	mut child := os.new_process(compiler)
	child.set_args(['-nocache', '-cc', 'clang', 'test', work + '/smb2'])
	child.run()
	child.wait()
	result := child.code
	child.close()
	if result != 0 { exit(result) }
	println('SMB2 production crypto, NTLMv2, parser, options and transport checks PASS')
}
