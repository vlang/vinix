// SPDX-License-Identifier: GPL-2.0-or-later
// Ordinary controls: explicit checks remain enabled in production builds.
module main

import os
import tools.packages.wineadapter

fn refuse(binary string, manifest string, patch string) ! {
	wineadapter.admit_forksafe_translator(binary, manifest, patch) or {
		unsafe { err.free() }
		return
	}
	return error('accepted a changed, missing, linked or non-file translator input')
}

fn run() ! {
	if os.args.len != 5 {
		return error('usage: wine-forksafe-admission BINARY MANIFEST PATCH FRESH_OUTPUT')
	}
	work := os.abs_path(os.args[4])
	if os.exists(work) { return error('output must be fresh') }
	os.mkdir_all(work)!
	paths := [work + '/binary', work + '/manifest', work + '/patch']!
	for i, path in paths { os.cp(os.args[i + 1], path)! }
	wineadapter.admit_forksafe_translator(paths[0], paths[1], paths[2])!
	mut refused := 0
	for path in paths {
		original := os.read_file(path)!
		defer { unsafe { original.free() } }
		for kind in ['changed', 'truncated', 'symlink', 'missing', 'directory']! {
			os.rm(path)!
			if kind == 'changed' {
				changed := original.clone()
				unsafe { changed.str[changed.len - 1] ^= 1 }
				os.write_file(path, changed)!
				unsafe { changed.free() }
			} else if kind == 'truncated' {
				os.write_file(path, '')!
			} else if kind == 'symlink' {
				os.write_file(path + '.target', original)!
				os.symlink(path + '.target', path)!
			} else if kind == 'directory' {
				os.mkdir(path)!
			}
			refuse(paths[0], paths[1], paths[2])!
			refused++
			if kind == 'directory' {
				os.rmdir(path)!
			} else if kind != 'missing' {
				os.rm(path)!
			}
			os.write_file(path, original)!
		}
		wineadapter.admit_forksafe_translator(paths[0], paths[1], paths[2])!
	}
	refuse(paths[1], paths[0], paths[2])!
	refused++
	if refused != 16 { return error('refusal control count differs') }
	println('FORKSAFE ADMISSION PASS 16 refusal cases and 4 exact successful admissions')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
