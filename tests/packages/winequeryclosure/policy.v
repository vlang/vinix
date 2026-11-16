// SPDX-License-Identifier: GPL-2.0-or-later
// Existence and xattr queries use exact admitted metadata paths.
module winequeryclosure

import tests.packages.winemetaclosure
import tests.packages.winereadclosure

fn project(files []string, aliases []string, operations string) !string {
	base := winemetaclosure.policy(files, aliases)!
	mut extra := '(deny ' + operations + ')\n(allow ' + operations + '\n'
	for root in winereadclosure.system_roots { extra += '  (subpath "' + root + '")\n' }
	for device in winereadclosure.devices { extra += '  (literal "' + device + '")\n' }
	for path in winemetaclosure.paths(files, aliases)! { extra += '  (literal "' + path + '")\n' }
	return base + extra + ')\n'
}

pub fn policy(files []string, aliases []string) !string {
	return project(files, aliases, 'file-test-existence file-read-xattr')
}

pub fn existence_policy(files []string, aliases []string) !string {
	return project(files, aliases, 'file-test-existence')
}

pub fn xattr_policy(files []string, aliases []string) !string {
	return project(files, aliases, 'file-read-xattr')
}

// Known output/record paths need existence checks before creating them.
// This grants neither data, metadata nor extended-attribute reads.
pub fn writes(paths []string) !string {
	if paths.len == 0 || paths.len > 16 { return error('bounded execution query paths required') }
	winereadclosure.policy(paths)!
	mut ordered := paths.clone(); ordered.sort()
	mut text := '(allow file-test-existence\n'
	for path in ordered { text += '  (literal "' + path + '")\n' }
	return text + ')\n'
}

// This pinned LLD creates output.tmp plus seven lowercase hexadecimal digits.
// Only existence checks for that bounded filename family are granted.
pub fn temporary_queries(output string) !string {
	winereadclosure.policy([output])!
	escaped := output.replace('.', '[.]').replace('+', '[+]')
	return '(allow file-test-existence\n  (regex #"^' + escaped + '[.]tmp' + '[0-9a-f]'.repeat(7) + '$")\n)\n'
}
