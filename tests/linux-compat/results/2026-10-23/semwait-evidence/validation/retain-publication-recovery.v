import crypto.sha256
import json2
import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/semwait-20261022'
	assert os.args.len == 2
	target := os.args[1] + '/validation'
	assert os.is_file(target + '/manifest.json')
	assert !os.exists(target + '/publication-recovery.json')
	mut files := map[string]string{}
	mut statuses := map[string]int{}
	for tag, wanted in {
		'publication-seal-h': 1
		'prepare-driver-h-compile': 0
		'publication-seal-h2': 0
		'finish-h-compile': 0
		'verify-h-compile': 0
		'retain-h-compile': 0
		'retain-validation-h': 0
		'publication-recovery-compile': 0
	} {
		actual := (os.read_file(area + '/' + tag + '.status') or { panic(err) }).trim_space()
		assert actual == wanted.str(), tag
		statuses[tag] = wanted
		for suffix in ['.command.json', '.log', '.status'] {
			name := tag + suffix
			assert !os.exists(target + '/' + name)
			bytes := os.read_bytes(area + '/' + name) or { panic(err) }
			os.write_file_array(target + '/' + name, bytes) or { panic(err) }
			files[name] = sha256.sum(bytes).hex()
		}
	}
	for name in ['retain-publication-recovery.v', 'retain-publication-recovery'] {
		bytes := os.read_bytes(area + '/' + name) or { panic(err) }
		os.write_file_array(target + '/' + name, bytes) or { panic(err) }
		files[name] = sha256.sum(bytes).hex()
	}
	readme := os.args[1] + '/README.md'
	text := os.read_file(readme) or { panic(err) }
	for line in text.split_into_lines() {
		mut tail := line
		for tail.contains('](') {
			tail = tail.all_after('](')
			link := tail.all_before(')')
			assert !link.starts_with('/') && !link.contains('..')
			assert os.is_file(os.args[1] + '/' + link), 'Missing index link: ' + link
			tail = tail.all_after(')')
		}
	}
	os.write_file(target + '/publication-recovery.json', json2.encode({
		'result': 'PASS'
		'scope': 'Retained host publication recovery records and index link check; kernel and guest evidence objects are unchanged.'
		'detail': 'The first h seal failed because V run removed its temporary helper executable. Recompiling the unchanged helper reproduced its exact recorded binary hash; the fresh h2 seal passed without changing original input ledgers.'
		'statuses': json2.encode(statuses)
		'files': json2.encode(files)
	}, prettify: true) + '\n') or { panic(err) }
	os.write_file(readme, text + '\nThe temporary publication-helper failure and exact-binary recovery are retained in the [publication recovery manifest](validation/publication-recovery.json).\n') or { panic(err) }
	println('Publication recovery records and index links: PASS')
}
