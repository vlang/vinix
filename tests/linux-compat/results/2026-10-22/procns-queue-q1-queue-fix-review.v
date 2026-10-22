import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/queue-fix'

fn body(source string, name string) !string {
	mut lines := []string{}
	mut found := false
	for line in source.split_into_lines() {
		if !found && !line.starts_with('\t') && line.contains(' ' + name + '(') && line.ends_with(' {') { found = true }
		if found {
			lines << line
			if line == '}' { return lines.join('\n') + '\n' }
		}
	}
	return error('missing generated function: ' + name)
}

fn main() {
	label := os.args[1]
	assert label in ['x86-track', 'x86-prod', 'arm-track', 'arm-prod']
	text := os.read_file(area + '/' + label + '/blob.c')!
	code := body(text, 'fs__reap_removed')!
	full := code.all_after('if (due == fs__removed_items.len) {').all_before('} else {')
	assert full.contains('items = fs__removed_items;')
	assert full.contains('fs__removed_items = array_new(')
	assert full.contains('sizeof(fs__RetiredItem), 0, 0);')
	assert !full.contains('clone') && !full.contains('free') && !full.contains('memcpy')
	assert code.count('array__free(&items);') == 1
	free_at := code.index('array__free(&items);') or { panic('missing final batch free') }
	callback_at := code.index('fs__free_node(node);') or { panic('missing final node callback') }
	assert free_at > callback_at
	assert code.contains('memcpy(items.data, fs__removed_items.data, (size_t)(due) * sizeof(fs__RetiredItem));')
	assert code.contains('array__delete_many(&fs__removed_items, 0, due);\n\t}\n\tklock__Lock__release(&fs__removed_lock);')
	assert text.contains('if (len == 0 && cap == 0) return (array){.element_size = elem_size, .flags = ArrayFlags__managed};')
	os.write_file(area + '/generated-reaper-' + label + '.c', code)!
	mut pins := []string{}
	for path in [area + '/' + label + '/blob.c', area + '/' + label + '/kernel/bin/vinix', area + '/generated-reaper-' + label + '.c', os.args[0] + '.v'] {
		pins << sha256.sum(os.read_bytes(path)!).hex() + '  ' + path
	}
	os.write_file(area + '/generated-review-' + label + '.sha256', pins.join('\n') + '\n')!
	message := label + ': PASS generated full-drain header transfer, zero-allocation global reset, unchanged partial detach and single final batch free after callbacks'
	os.write_file(area + '/generated-review-' + label + '.log', message + '\n')!
	os.write_file(area + '/generated-review-' + label + '.status', '0\n')!
	println(message)
}
