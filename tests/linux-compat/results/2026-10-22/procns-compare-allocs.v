import os

fn groups(path string) map[string]int {
	mut counts := map[string]int{}
	for line in (os.read_file(path) or { panic(err) }).split_into_lines() {
		parts := line.split(':')
		if parts.len < 3 || parts[1] == '' || !parts[1].bytes().all(it.is_digit()) { continue }
		key := parts[0] + ' ' + line.all_after(':').all_after(':').all_after(' ')
		counts[key]++
	}
	return counts
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/'
	before := groups(area + 'allocs-base.log')
	after := groups(area + 'allocs.log')
	mut keys := before.keys()
	for key in after.keys() { if key !in before { keys << key } }
	keys.sort()
	println('allocation groups: baseline=${before.len} candidate=${after.len}')
	for key in keys { if before[key] != after[key] { println('${key}: ${before[key]}/${after[key]}') } }
	for label in ['allocs-base', 'allocs'] {
		lines := os.read_file(area + label + '.log')!.split_into_lines()
		println('${label}: ' + lines.filter(it.starts_with('aarch64:') || it.starts_with('x86_64:')).join('; ') + ', excess groups=' + lines.filter(it.starts_with('NEW:')).len.str())
	}
}
