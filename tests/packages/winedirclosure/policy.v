// SPDX-License-Identifier: GPL-2.0-or-later
// Directory data reads are limited to exact ancestors of admitted files.
module winedirclosure

import os
import tests.packages.winereadclosure

pub fn directories(files []string) ![]string {
	// Validate every literal before deriving any policy text, including bounds,
	// duplicates and characters that could escape an SBPL string.
	winereadclosure.policy(files)!
	mut found := map[string]bool{}
	for file in files {
		mut parent := os.dir(file)
		for {
			found[parent] = true
			if found.len > 32768 { return error('directory capability count outside bound') }
			if parent == '/' { break }
			parent = os.dir(parent)
		}
	}
	mut result := found.keys(); result.sort()
	return result
}

pub fn policy(files []string) !string {
	base := winereadclosure.policy(files)!
	broad := '(allow file-read-data (vnode-type DIRECTORY))\n'
	if base.count(broad) != 1 { return error('unsupported file-data policy projection') }
	mut exact := '(allow file-read-data (require-all (vnode-type DIRECTORY) (require-any\n'
	for directory in directories(files)! { exact += '  (literal "' + directory + '")\n' }
	exact += ')))\n'
	return base.replace(broad, exact)
}
