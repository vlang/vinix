// SPDX-License-Identifier: Apache-2.0
// V replacement for AOSP build/tools/findleaves.py.
// Original algorithm: Copyright (C) 2009 The Android Open Source Project.
module artgenerators

import os
import strconv

fn descend(root string, filename string, depth int, minimum int, prune []string,
	ancestors []string, mut found map[string]bool) ! {
	if !os.is_dir(root) { return }
	if depth > 128 { return error('Makefile search exceeds directory depth bound') }
	real := os.real_path(root)
	if real in ancestors { return error('Makefile search contains a symlink cycle: ' + root) }
	mut lineage := ancestors.clone()
	lineage << real
	names := os.ls(root)!
	if depth >= minimum && filename in names && !os.is_dir(root + '/' + filename) {
		found[root.trim_right('/') + '/' + filename] = true
		return
	}
	for name in names {
		if name !in prune && os.is_dir(root + '/' + name) {
			descend(root.trim_right('/') + '/' + name, filename, depth + 1, minimum,
				prune, lineage, mut found)!
		}
	}
}

pub fn find_leaves(args []string) ![]string {
	mut minimum := -1
	mut prune := []string{}
	mut i := 0
	for i < args.len && args[i].starts_with('--') {
		arg := args[i]
		if arg.starts_with('--mindepth=') {
			text := arg.all_after('=')
			minimum = int(strconv.parse_int(text, 10, 32) or { return error('invalid --mindepth') })
		} else if arg.starts_with('--prune=') && arg.all_after('=') != '' {
			prune << arg.all_after('=')
		} else { return error('unknown or empty discovery option: ' + arg) }
		i++
	}
	if args.len - i < 2 { return error('expected directories and filename') }
	filename := args.last()
	if filename == '' || filename.contains('/') { return error('expected leaf filename') }
	mut found := map[string]bool{}
	for root in args[i..args.len - 1] {
		descend(root, filename, 1, minimum, prune, []string{}, mut found)!
	}
	mut result := found.keys()
	result.sort()
	return result
}
