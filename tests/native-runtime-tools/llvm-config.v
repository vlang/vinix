// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	if os.args.len == 3 && os.args[1] == '--install' {
		os.cp(os.executable(), os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		os.chmod(os.args[2], 0o755) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	directory := os.dir(os.real_path(os.executable()))
	root := directory + '/sysroot'
	base := root + '/usr/lib/llvm-15'
	args := os.args[1..]
	if '--version' in args {
		version := os.read_file(directory + '/.llvm-config-version') or {
			eprintln(err)
			exit(1)
		}
		println(version.trim_space())
	} else if '--components' in args {
		mut available := []string{}
		for pair in [['bitwriter', 'BitWriter'], ['engine', 'ExecutionEngine'],
			['mcdisassembler', 'MCDisassembler'], ['mcjit', 'MCJIT'], ['core', 'Core'],
			['executionengine', 'ExecutionEngine'], ['scalaropts', 'ScalarOpts'],
			['transformutils', 'TransformUtils'], ['instcombine', 'InstCombine'],
			['native', 'X86CodeGen'], ['coroutines', 'Coroutines'], ['lto', 'LTO']] {
			if os.is_file(base + '/lib/libLLVM' + pair[1] + '.a') { available << pair[0] }
		}
		println(available.join(' '))
	} else if '--cppflags' in args {
		println('-I${base}/include -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS')
	} else if '--shared-mode' in args {
		println('shared')
	} else if '--libs' in args || '--ldflags' in args {
		println('-L${root}/usr/lib/x86_64-linux-gnu -lLLVM-15')
	} else if '--libdir' in args {
		println(root + '/usr/lib/x86_64-linux-gnu')
	} else if '--has-rtti' in args {
		println('YES')
	} else {
		eprintln('unsupported LLVM 15 cross query: ' + args.str())
		exit(1)
	}
}
