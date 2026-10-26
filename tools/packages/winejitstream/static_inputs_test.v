// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

import os
import time

#define wine_static_mkfifo mkfifo
#define wine_static_unlink unlink
fn C.wine_static_mkfifo(&char, u32) int
fn C.wine_static_unlink(&char) int

fn static_test_root() !string {
	base := os.getenv('TMPDIR')
	static_directory(base)!
	root := base + '/wine-static-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	os.mkdir(root)!
	for name in ['include', 'lib', 'gcc'] { os.mkdir(root + '/' + name)! }
	os.mkdir(root + '/include/nested')!
	os.mkdir(root + '/include/c++')!
	os.write_file(root + '/include/stdio.h', 'header')!
	os.write_file(root + '/include/nested/deep.h', 'nested')!
	os.write_file(root + '/include/c++/excluded', 'excluded')!
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a', 'libm.a', 'libpthread.a'] {
		os.write_file(root + '/lib/' + name, name)!
	}
	for name in ['crtbegin.o', 'crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] {
		os.write_file(root + '/gcc/' + name, name)!
	}
	return root
}

fn static_test_plan(root string) !StaticPlan {
	return static_input_plan(root + '/include', root + '/lib', root + '/gcc')
}

fn static_expect(condition bool, message string) {
	if !condition { panic('wine-static control: ' + message) }
}

fn static_test_refused(root string) {
	static_test_plan(root) or { return }
	static_expect(false, 'invalid static input admitted')
}

fn test_static_inputs_copy_and_exact_manifest() {
	root := static_test_root()!
	defer { os.rmdir_all(root) or {} }
	plan := static_test_plan(root)!
	static_expect(plan.entries.len == 13, 'expected selected file count')
	static_expect(plan.entries.filter(it.relative.contains('/c++/')).len == 0, 'root C++ excluded')
	static_expect(plan.entries.filter(it.relative.ends_with('/nested/deep.h')).len == 1, 'nested C retained')
	output := root + '/out'
	static_input_copy(plan, output, 0, 0, 0)!
	static_input_recheck(plan)!
	static_output_verify(plan, output)!
	static_expect(static_state_bytes(output)! == plan.bytes, 'output exact byte count')
	os.write_file(output + '/unexpected', 'extra')!
	static_output_verify(plan, output) or { return }
	static_expect(false, 'extra output entry admitted')
}

fn test_static_inputs_refuse_links_dangling_special_and_missing() {
	root := static_test_root()!
	defer { os.rmdir_all(root) or {} }
	path := root + '/include/nested/bad'
	for target in [root + '/include/stdio.h', root + '/include/nested', root + '/absent'] {
		os.symlink(target, path)!
		static_test_refused(root)
		removed := C.wine_static_unlink(path.str)
		static_expect(removed == 0, 'literal test link cleanup failed')
	}
	created := C.wine_static_mkfifo(path.str, 0o600)
	static_expect(created == 0, 'create special-file fixture')
	static_test_refused(root)
	os.rm(path)!
	os.rm(root + '/gcc/crtbegin.o')!
	static_test_refused(root)
}

fn test_static_inputs_budget_and_collision_refuse_before_mkdir() {
	root := static_test_root()!
	defer { os.rmdir_all(root) or {} }
	plan := static_test_plan(root)!
	static_expect(static_budget(static_input_limit - plan.bytes - 1, plan.bytes, 1)! == static_input_limit, 'exact budget boundary')
	output := root + '/out'
	mut refused := false
	static_input_copy(plan, output, static_input_limit - plan.bytes, 1, 0) or { refused = true }
	static_expect(refused && !os.exists(output), 'budget refuses before mkdir')
	os.symlink(root + '/absent', output)!
	refused = false
	static_input_copy(plan, output, 0, 0, 0) or { refused = true }
	static_expect(refused && os.is_link(output), 'dangling collision retained')
	removed := C.wine_static_unlink(output.str)
	static_expect(removed == 0, 'literal dangling test link cleanup')
	os.mkdir(output)!
	os.write_file(output + '/retained', 'retain')!
	refused = false
	static_input_copy(plan, output, 0, 0, 0) or { refused = true }
	static_expect(refused && os.read_file(output + '/retained')! == 'retain', 'ordinary collision retained')
}

fn test_static_receipt_projection_and_actual_length() {
	static_expect(static_receipt_projection(static_input_limit - 15, 7, 2, 3, 3)! == static_input_limit,
		'projected fixed receipts and reserve exact boundary')
	mut refused := false
	static_receipt_projection(static_input_limit - 15, 7, 2, 3, 4) or { refused = true; u64(0) }
	static_expect(refused, 'projected receipts refuse one byte over before writing')
	static_receipt_check('1234', 4)!
	refused = false
	static_receipt_check('12345', 4) or { refused = true }
	static_expect(refused, 'actual receipt refuses larger than admitted bound')
	refused = false
	static_receipt_projection(~u64(0), 1, 1, 1, 1) or { refused = true; u64(0) }
	static_expect(refused, 'projection refuses overflow')
}

fn test_static_inputs_source_mutation_and_overlap_refuse_before_mkdir() {
	root := static_test_root()!
	defer { os.rmdir_all(root) or {} }
	plan := static_test_plan(root)!
	for output in [root + '/include/out', root + '/gcc/out'] {
		mut refused := false
		static_input_copy(plan, output, 0, 0, 0) or { refused = true }
		static_expect(refused && !os.exists(output), 'overlap refuses before mkdir')
	}
	os.write_file(root + '/include/stdio.h', 'changed')!
	mut refused := false
	static_input_copy(plan, root + '/out', 0, 0, 0) or { refused = true }
	static_expect(refused && !os.exists(root + '/out'), 'byte mutation refuses before mkdir')
	os.rm(root + '/include/stdio.h')!
	refused = false
	static_input_copy(plan, root + '/out', 0, 0, 0) or { refused = true }
	static_expect(refused && !os.exists(root + '/out'), 'deletion refuses before mkdir')
	os.symlink(root + '/include/nested/deep.h', root + '/include/stdio.h')!
	refused = false
	static_input_copy(plan, root + '/out', 0, 0, 0) or { refused = true }
	static_expect(refused && !os.exists(root + '/out'), 'retarget refuses before mkdir')
}

fn test_static_inputs_detect_output_byte_and_type_mutations() {
	root := static_test_root()!
	defer { os.rmdir_all(root) or {} }
	plan := static_test_plan(root)!
	output := root + '/out'
	static_input_copy(plan, output, 0, 0, 0)!
	path := output + '/' + static_input_triple + '/include/stdio.h'
	os.write_file(path, 'mutate')!
	mut refused := false
	static_output_verify(plan, output) or { refused = true }
	static_expect(refused, 'output byte mutation refused')
	os.rm(path)!
	os.symlink(root + '/include/stdio.h', path)!
	refused = false
	static_output_verify(plan, output) or { refused = true }
	static_expect(refused, 'output type mutation refused')
}

fn test_static_driver_recipe_rejects_original_escaped_and_missing_startup() {
	root := static_test_root()!
	defer { os.rmdir_all(root) or {} }
	plan := static_test_plan(root)!
	output := root + '/out'
	static_input_copy(plan, output, 0, 0, 0)!
	include := output + '/x86_64-linux-musl/include'
	lib := output + '/x86_64-linux-musl/lib'
	gcc := output + '/lib/gcc/x86_64-linux-musl/14.2.0'
	text := '-internal-isystem "' + include + '" -L' + lib + ' -L' + gcc + ' '
		+ lib + '/crt1.o ' + lib + '/crti.o ' + lib + '/crtn.o '
		+ gcc + '/crtbeginT.o ' + gcc + '/crtend.o'
	static_expect(static_driver_recipe_check(text, output, root + '/include', '/original')!.len == 3, 'expected driver candidates')
	static_expect(static_driver_recipe_check(text + ' -I ' + include + ' -L' + lib + ' -c-isystem=' + include
		+ ' ' + lib + '/libc.a', output, root + '/include', '/original')!.len == 6, 'retained split and joined candidates')
	for bad in [text + ' /original/lib/libc.a', text + ' -L' + root + '/lib',
		text + ' ' + root + '/gcc/crtbegin.o', text + ' ' + root + '/gcc/Scrt1.o',
		text + ' -I ' + root + '/lib', text + ' -I' + root + '/lib',
		text + ' -L ' + root + '/lib', text + ' -c-isystem ' + root + '/lib',
		text + ' -iquote' + root + '/lib', text + ' -isystem=' + root + '/lib',
		text + ' -internal-iframework ' + root + '/lib', text + ' ' + root + '/lib/libc.a',
		text + ' -I relative', text + ' -Irelative', text + ' -Lrelative', text + ' -I=',
		text.replace(gcc + '/crtbeginT.o', root + '/gcc/crtbeginT.o'),
		text.replace(gcc + '/crtend.o', '')] {
		mut refused := false
		static_driver_recipe_check(bad, output, root + '/include', '/original') or { refused = true; []string{} }
		static_expect(refused, 'bad driver recipe refused')
	}
	os.mkdir(root + '/out-sibling')!
	mut refused := false
	static_driver_recipe_check(text + ' -I' + root + '/out-sibling', output, root + '/include', '/original') or {
		refused = true
		[]string{}
	}
	static_expect(refused, 'sibling-prefix search escape refused')
}

fn test_static_assertions_are_active() {
	if os.getenv('VINIX_WINE_STATIC_ASSERT_SENTINEL') == '1' {
		static_expect(false, 'wine-static intentional assertion sentinel')
	}
}
