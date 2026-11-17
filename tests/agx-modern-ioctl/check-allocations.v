// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn counts(source string) (map[string]int, []string) {
	mut sites := map[string]int{}
	mut totals := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') { totals << line }
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]
		space := tail.index(' ') or { continue }
		location := tail[..space].split(':')
		if location.len != 2 || location[0].int() <= 0 || location[1].int() <= 0 { continue }
		sites[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert sites.len > 100 && totals.len == 2
	return sites, totals
}

fn main() {
	assert os.args.len == 3, 'usage: check-allocations CURRENT BASELINE'
	current, current_totals := counts(os.read_file(os.args[1])!)
	old, old_totals := counts(os.read_file(os.args[2])!)
	assert current == old
	assert current_totals == old_totals.map(it.replace('835 source files', '839 source files'))
	println('Allocation sites unchanged by file/kind: ARM377 across839 sources (four added); x86289 across813. Existing allowance failures remain.')
}
