// SPDX-License-Identifier: GPL-2.0-only
module archivehost

import hosttest
import os
import strconv

fn path_text(path string) string {
	prefix := if path.starts_with('//') && !path.starts_with('///') {
		'//'
	} else if path.starts_with('/') {
		'/'
	} else {
		''
	}
	value := prefix + path.split('/').filter(it != '' && it != '.').join('/')
	return if value == '' { '.' } else { value }
}

pub fn run(kind string, args []string) {
	usage := match kind {
		'parts' { 'usage: split-qemu-initramfs SOURCE DIRECTORY [--max-bytes BYTES]' }
		'desktop' { 'usage: split-desktop-initramfs SOURCE BASE ROOT_SEED MANIFEST' }
		else { 'usage: build-qemu-module-iso SOURCE OUTPUT' }
	}
	options := if kind == 'parts' {
		[hosttest.Option{'--max-bytes', true, []string{}}]
	} else {
		[]hosttest.Option{}
	}
	parsed := hosttest.parse_arguments(args, options, if kind == 'desktop' { 4 } else { 2 }, usage,
		'Build and cache QEMU boot artifacts from a streaming native archive input.') or {
		eprintln(usage)
		eprintln(err.msg())
		exit(2)
	}
	mut limit := default_max_bytes
	if kind == 'parts' && '--max-bytes' in parsed.options {
		number := strconv.parse_int(parsed.options['--max-bytes'].trim_space(), 10, 64) or {
			eprintln('argument --max-bytes: invalid integer')
			exit(2)
		}
		if number < 20480 || number > 4294967295 {
			eprintln("--max-bytes must be between 20480 and FAT32's 4 GiB limit")
			exit(2)
		}
		limit = u64(number)
	}
	paths := parsed.positional.map(path_text(it))
	if kind != 'desktop' {
		// resolve(strict=True) reported missing input as an I/O failure.
		source := hosttest.resolve_path(paths[0]) or {
			eprintln(err)
			exit(1)
		}
		os.stat(source) or {
			eprintln(err)
			exit(1)
		}
	}
	if !regular(paths[0]) {
		eprintln(if kind == 'desktop' {
			'desktop initramfs is missing: ' + paths[0]
		} else {
			'not a regular file: ' + paths[0]
		})
		exit(2)
	}
	if kind == 'iso' {
		source := hosttest.resolve_path(paths[0]) or {
			eprintln(err)
			exit(1)
		}
		if source == absolute(paths[1]) {
			eprintln('source and ISO output must differ')
			exit(2)
		}
		os.find_abs_path_of_executable('xorriso') or {
			eprintln('xorriso is required to build the QEMU module ISO')
			exit(2)
		}
	}
	execute(kind, paths, limit) or {
		eprintln(err.msg())
		exit(1)
	}
}

fn execute(kind string, paths []string, limit u64) ! {
	match kind {
		'parts' {
			for part in qemu_split(paths[0], paths[1], limit)! { println(part) }
		}
		'desktop' { desktop_split(paths[0], paths[1], paths[2], paths[3])! }
		else { module_iso(paths[0], paths[1])! }
	}
}
