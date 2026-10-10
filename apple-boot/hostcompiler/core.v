// SPDX-License-Identifier: GPL-2.0-or-later
module hostcompiler

import hosttest
import os

fn has_printf_macro(text string) bool {
	mut begin := 0
	for index, ch in (text + ' ').bytes() {
		if hosttest.word_char(ch) { continue }
		word := text[begin..index]
		if word.starts_with('PRI') && word.len > 3 && word[3..].bytes().all(it.is_alnum()) {
			return true
		}
		begin = index + 1
	}
	return false
}

pub fn generate(output string, host bool) ! {
	root := hosttest.root()
	compiler := hosttest.command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', root], '', -1, os.environ())!.stdout
	work := hosttest.work_dir('', 'vinix-apple-v-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	source := work + '/applecore'
	hosttest.module_copy_tree(root + '/apple-boot/vcore', source)!
	if host {
		for name in os.ls(source)! {
			if !name.ends_with('.v') || !os.is_file(source + '/' + name) { continue }
			path := source + '/' + name
			mut text := os.read_file(path)!
			for symbol in ['memcpy', 'memmove', 'memset', 'memcmp', 'strlen', 'strcmp'] {
				text = text.replace("@[export: '" + symbol + "']", "@[export: 'apple_boot_host_" + symbol + "']")
			}
			os.write_file(path, text)!
		}
	}
	os.write_file(work + '/v.mod', "Module {name: 'apple_boot'}\n")!
	os.write_file(work + '/entry.v', 'module main\nimport applecore as _\n')!
	mut environment := os.environ()
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	result := hosttest.capture([compiler, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix',
		'-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o', output, work],
		'', -1, environment)!
	print(result.stdout)
	eprint(result.stderr)
	if result.code != 0 { return error('V compiler failed (${result.code})') }
	text := os.read_file(output)!
	if has_printf_macro(text) {
		return error('freestanding loader contains an integer printf macro')
	}
	os.write_file(output, text.replace('#include <inttypes.h>\n', ''))!
}
