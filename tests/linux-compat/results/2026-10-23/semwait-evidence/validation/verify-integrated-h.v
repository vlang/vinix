import crypto.sha256
import json2
import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/semwait-20261022'
	root := '/Users/alex/code/vinix'
	copies := json2.decode[map[string]string](os.read_file(area + '/source-integration-applied.json') or { panic(err) }) or { panic(err) }
	for relative, original in copies {
		assert (os.read_bytes(root + '/' + relative) or { panic(err) }) == (os.read_bytes(original) or { panic(err) }), 'Intervening edit: ' + relative
	}
	assert (os.read_bytes(root + '/tests/linux-compat/semwait-evidence.v') or { panic(err) }) == (os.read_bytes(area + '/semwait-evidence-h.v') or { panic(err) })
	kernel := os.read_bytes(root + '/kernel/sysvsem/sysvsem.v') or { panic(err) }
	assert sha256.sum(kernel).hex() == '6043c737cf9d66a1329cab5cfb8bbedb1426afae9b446854e1167fb54548703f'
	println('Qualified integration: PASS (' + copies.len.str() + ' exact source copies plus maintained checker)')
}
