// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn inspect(image macho.Image, show_imports bool) ! {
	architecture := match image.subtype & 0xffffff {
		0 { 'ARM64' }
		2 { 'ARM64e' }
		else { 'ARM64/subtype ${image.subtype & 0xffffff}' }
	}
	println('${architecture} ${image.platform_name()} Mach-O, ${image.segments.len} segments')
	println('Minimum OS: ${image.minos >> 16}.${(image.minos >> 8) & 0xff}.${image.minos & 0xff}')
	println('Chained fixups: ${image.fixup_size} bytes; encrypted: ${image.encrypted}')
	for library in image.libraries {
		println('Dependency: ${library.name}${if library.weak { ' (weak)' } else { '' }}')
	}
	symbols := image.imported_symbols()!
	table := if image.fixup_size != 0 { 'chained fixups' } else { 'symbol table' }
	println('Imports: ${symbols.len} (${table})')
	if show_imports {
		for symbol in symbols {
			println('Import: ${symbol.library} ${symbol.name}${if symbol.weak {
				' (weak)'
			} else {
				''
			}}')
		}
	}
	issues := image.execution_issues()
	if issues.len == 0 {
		println('Image metadata is supported; imports and fixups are checked during execution.')
	} else {
		for issue in issues { println('Unsupported: ${issue}') }
	}
}

fn main() {
	launcher := os.file_name(os.args[0])
	if launcher == 'vinix-ios-ppsspp' {
		if os.args.len > 2 { eprintln('usage: vinix-ios-ppsspp [PSP game file]'); exit(2) }
		if os.args.len == 2 { C.setenv(c'VINIX_IOS_OPEN_FILE', unsafe { &char(os.args[1].str) }, 1) }
		documents := os.getenv('VINIX_IOS_DOCUMENTS')
		user_home := os.getenv('VINIX_USER_HOME')
		path := if documents.len > 0 { documents } else { os.join_path(if user_home.len > 0 { user_home } else { '/root' }, '.local', 'share', 'vinix', 'ppsspp', 'Documents') }
		os.mkdir_all(os.join_path(path, 'PSP', 'SYSTEM')) or { eprintln('iOS: ${err}'); exit(1) }
		preferences := os.join_path(path, 'PSP', 'SYSTEM', 'ppsspp.ini')
		if !os.exists(preferences) { os.write_file(preferences, '[Sound]\nEnable=False\n') or { eprintln('iOS: ${err}'); exit(1) } }
		C.setenv(c'VINIX_IOS_DOCUMENTS', unsafe { &char(path.str) }, 0)
		C.setenv(c'VINIX_IOS_EXIT_ON_CLOSE', c'1', 0)
		binary := '/usr/share/vinix/ios/PPSSPP.app/PPSSPP'
		run_binary(binary, [binary])
		return
	}
	if launcher in ['vinix-ios-calculator', 'vinix-ios-2048'] {
		name := if launcher == 'vinix-ios-calculator' { 'Calculator' } else { 'NumberTileGame' }
		path := '/usr/share/vinix/ios/${name}.app/${name}'
		run_binary(path, [path])
		return
	}
	if os.args.len < 2 || os.args[1] in ['--help', '-h'] {
		println('usage: run-ios [--inspect|--imports] <ARM64 Mach-O executable> [arguments...]')
		if os.args.len < 2 { exit(2) }
		return
	}
	inspection := os.args[1] in ['--inspect', '--imports']
	index := if inspection { 2 } else { 1 }
	if os.args.len <= index {
		eprintln('iOS: executable path is missing')
		exit(2)
	}
	data := os.read_bytes(os.args[index]) or {
		eprintln('iOS: ${err}')
		exit(1)
	}
	image := macho.parse(data) or {
		eprintln(err)
		exit(1)
	}
	if inspection {
		inspect(image, os.args[1] == '--imports') or {
			eprintln(err)
			exit(1)
		}
		return
	}
	status := execute(image, os.args[index..]) or {
		eprintln(err)
		exit(1)
	}
	exit(status)
}

fn run_binary(path string, arguments []string) {
	data := os.read_bytes(path) or {
		eprintln('iOS: ${err}')
		exit(1)
	}
	image := macho.parse(data) or {
		eprintln(err)
		exit(1)
	}
	status := execute(image, arguments) or {
		eprintln(err)
		exit(1)
	}
	exit(status)
}
