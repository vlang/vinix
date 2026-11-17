// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn counts(source string) (map[string]int, []string) {
	mut sites := map[string]int{}; mut totals := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') { totals << line }
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]; space := tail.index(' ') or { continue }
		location := tail[..space].split(':')
		if location.len != 2 || location[0].int() <= 0 || location[1].int() <= 0 { continue }
		sites[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert sites.len > 100 && totals.len == 2; return sites, totals
}
fn main() {
	assert os.args.len == 3
	a, ta := counts(os.read_file(os.args[1])!)
	mut b, tb := counts(os.read_file(os.args[2])!)
	key := 'gpu/agx/gpu/g13.v struct on the heap'
	assert b[key] > 0; b[key]--
	assert a == b && ta == tb.map(it.replace('379 allocation sites', '378 allocation sites')),
		'only the verified queue-record allocation may leave the report; all other per-file/per-kind sites and source counts match'
	println('Allocation comparison: only verified G13 queue-record site removed, ARM379 to378 with835 source files; x86 remains289/813. Remaining allowance failures persist.')
}
