// SPDX-License-Identifier: GPL-2.0-or-later
// Metadata reads use exact admitted file/ancestor literals and OS exceptions.
module winemetaclosure

import tests.packages.winedirclosure
import tests.packages.winereadclosure

pub fn paths(files []string, aliases []string) ![]string {
	if aliases.len > 128 { return error('metadata alias count outside bound') }
	combined := [...files, ...aliases]
	mut selected := map[string]bool{}
	for directory in winedirclosure.directories(combined)! { selected[directory] = true }
	for file in combined { selected[file] = true }
	mut result := selected.keys(); result.sort()
	return result
}

pub fn policy(files []string, aliases []string) !string {
	base := winedirclosure.policy(files)!
	mut metadata := '(deny file-read-metadata)\n(allow file-read-metadata\n'
	for root in winereadclosure.system_roots { metadata += '  (subpath "' + root + '")\n' }
	for device in winereadclosure.devices { metadata += '  (literal "' + device + '")\n' }
	for path in paths(files, aliases)! { metadata += '  (literal "' + path + '")\n' }
	return base + metadata + ')\n'
}
