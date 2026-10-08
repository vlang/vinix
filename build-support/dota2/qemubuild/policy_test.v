// SPDX-License-Identifier: GPL-2.0-or-later
module qemubuild

import hosttest
import json2
import os

fn test_generation_json_retains_python_spelling() {
	value := json2.Any({
		'z': json2.Any(['é', '😀', '\x7f'].map(json2.Any(it)))
		'a': json2.Any('\\"')
	})
	assert dumps(value, true, false) == '{"a": "\\\\\\"", "z": ["\\u00e9", "\\ud83d\\ude00", "\\u007f"]}'
	assert dumps(json2.Any([]json2.Any{}), false, true) == '[]'
	assert strip_space('\x1c\u2003generation\u3000\x1f') == 'generation'
}

fn test_gcc_versions_preserve_python_integer_domain() {
	assert version_integer(' \u2003+１_２３\u3000 ')!.str() == '123'
	assert version_integer('-１２')!.str() == '-12'
	assert version_integer('9'.repeat(200))!.str() == '9'.repeat(200)
	assert version_less(gcc_version('12.2')!, gcc_version('12.2.0')!)
	for value in ['', '+', '1__2', '_1', '1_', 'one', '\x1c1'] {
		mut rejected := false
		version_integer(value) or { rejected = true }
		assert rejected
	}
}

fn test_header_tree_hash_uses_path_components_and_link_targets() {
	work := hosttest.work_dir('dota-qemu-policy', '')!
	defer { hosttest.remove_work_dir(work) or {} }
	for name, contents in {
		'a/z':     'z'
		'a.a':     'a'
		'a/b':     'b'
		'd\\x/子': 'c'
	} {
		path := join(work, name)
		mkdir(path.all_before_last('/'), true, true)!
		write(path, contents)!
	}
	os.symlink('a', join(work, 'dir-link'))!
	assert tree_digest(work)! == '72d83aadbfb7e2622af9f89076602552eea7325e15a1f3b400a8e06dd270916d'
}
