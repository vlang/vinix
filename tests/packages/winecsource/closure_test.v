// SPDX-License-Identifier: GPL-2.0-or-later
module winecsource

import os
import json2

fn require_check(ok bool) { if !ok { panic('WINE helper control failed') } }
fn require_refusal(ok bool) { if !ok { panic('WINE helper expected refusal') } }

fn test_trace_preserves_absolute_paths_spaces_order_and_repetition() {
	require_check(trace('. /one header.h\n.. /two.h\n. /one header.h\ncompiler note\n')! == ['/one header.h', '/two.h', '/one header.h'])
	for text in ['', 'diagnostics only\n', '. relative.h\n', '. /file\r\n', '. /file\x00\n'] {
		mut refused := false
		trace(text) or { refused = true }
		require_refusal(refused)
	}
}

fn test_real_two_unit_compilation_admits_hidden_header_and_refuses_mutations() {
	root := os.real_path(os.temp_dir()) + '/vinix-c-closure-' + os.getpid().str()
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	header := root + '/hidden header.h'
	os.write_file(header, 'int token(void);\n')!
	os.write_file(root + '/one.c', '#include "' + header + '"\nint main(void) { return token(); }\n')!
	os.write_file(root + '/two.c', '#include "' + header + '"\nint token(void) { return 0; }\n')!
	clang := os.find_abs_path_of_executable('clang')!
	base := [clang, '-O1', '-w', root + '/one.c', root + '/two.c', '-lm', '-lpthread', '-o', root + '/program']
	build(base, root, root)!
	admit(root, root)!
	proof := json2.decode[Proof](os.read_file(root + '/c-inputs-before.json')!)!
	require_check(proof.includes.filter(it.path == header).len == 2)
	require_check(header in inputs(root)!)
	// A changed header outside any manual seed tree must refuse.
	os.write_file(header, 'int different(void);\n')!
	mut refused := false
	admit(root, root) or { refused = true }
	require_refusal(refused)
	os.write_file(header, 'int token(void);\n')!
	// A different resolved target refuses even when its bytes are identical.
	os.rename(header, root + '/saved')!
	os.symlink(root + '/saved', header)!
	refused = false
	admit(root, root) or { refused = true }
	require_refusal(refused)
	os.rm(header)!; os.rename(root + '/saved', header)!
	admit(root, root)!
	before := os.read_file(root + '/c-inputs-before.json')!
	verified := os.read_file(root + '/c-inputs-verified.json')!
	cc_log := os.read_file(root + '/cc.log')!
	os.write_file(root + '/cc.log', '. ' + header + '\n')!
	refused = false
	admit(root, root) or { refused = true }
	require_refusal(refused)
	os.write_file(root + '/cc.log', cc_log)!
	changed := Proof{sources: proof.sources, includes: proof.includes[..1]}
	for name in ['c-inputs-before.json', 'c-inputs-verified.json'] { os.write_file(root + '/' + name, json2.encode(changed))! }
	refused = false
	admit(root, root) or { refused = true }
	require_refusal(refused)
	os.write_file(root + '/c-inputs-before.json', before)!
	os.write_file(root + '/c-inputs-verified.json', verified)!
	os.rename(root + '/c-inputs-before.json', root + '/saved-proof')!
	os.symlink(root + '/saved-proof', root + '/c-inputs-before.json')!
	refused = false
	admit(root, root) or { refused = true }
	require_refusal(refused)
}
