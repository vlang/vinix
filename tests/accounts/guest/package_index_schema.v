// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import os
import tools.packages.pkgcore
import tools.packages.signing

fn qualify_package_index_schema(mut t Test) ! {
	service := pkgcore.Service{}
	directory := pkgcore.state_directory('')
	state := service.state()!
	catalog := os.read_file(directory + '/catalog.json')!
	for index in 0 .. 4 {
		result := run(['/sbin/init', 'package-index-case', index.str()], '', none, none)
		assert result.status == 0, result.output
	}
	package_success(['update'])!
	assert service.state()! == state && os.read_file(directory + '/catalog.json')! == catalog
	t.say('PACKAGE INDEX signed-duplicate missing-declaration null-array typed-counter refusal preserves-catalog-trust-state canonical-retry PASS')
}

// Each case uses the service's one-shot process lifetime. Repeated generic JSON
// decoding in this deliberately manual-memory fixture otherwise accumulates
// mapping charges before it can execute the final canonical retry.
fn qualify_package_index_case(mut t Test, index int) ! {
	assert index >= 0 && index < 4
	service := pkgcore.Service{}
	directory := pkgcore.state_directory('')
	state := service.state()!
	catalog := os.read_file(directory + '/catalog.json')!
	history := os.read_file(directory + '/trust-history.json')!
	configuration := os.read_file('/etc/vinix-packages/config.json')!
	workspace := '/tmp/admin-repository'
	text := os.read_file(workspace + '/index.json')!
	original_signature := os.read_file(workspace + '/index.sig')!
	seed := hex.decode(os.read_file('/tmp/package-publisher/admin-seed')!.trim_space())!
	private_key := signing.new_key_from_seed(seed)
	repository := pkgcore.load_config('')!.repositories[0]
	broken := [text.replace('"sequence":1', '"sequence":2,"sequ\\u0065nce":2'),
		text.replace('"sequence":1', '"sequence":"2"'),
		text.replace('"sequence":1', '"sequence":2').replace('"firmware":false,', ''),
		text.replace('"sequence":1', '"sequence":2').replace('"permissions":[]', '"permissions":null')][index]
	bytes := broken.bytes()
	signature := signing.sign(private_key, bytes)!
	os.write_file(workspace + '/index.json', broken)!
	os.write_file(workspace + '/index.sig', signature.hex())!
	unsafe { bytes.free(); signature.free() }
	// Exercise the staged service executable, then the enrollment writer.
	t.say('PACKAGE INDEX case ' + index.str() + ' update')
	result := run(['/usr/bin/vinix-package', 'update'], '', none, none)
	assert result.status == 1 && !result.output.contains('V panic:'), result.output
	t.say('PACKAGE INDEX case ' + index.str() + ' enrollment')
	mut refused := false
	pkgcore.enroll_repository('', repository, true) or { refused = true }
	assert refused
	assert os.read_file(directory + '/catalog.json')! == catalog && os.read_file(directory + '/trust-history.json')! == history
	assert os.read_file('/etc/vinix-packages/config.json')! == configuration && service.state()! == state
	assert !os.exists(directory + '/refresh') && !os.exists(directory + '/enrollment')
	t.say('PACKAGE INDEX case ' + index.str() + ' verify')
	assert service.verify()! == state
	t.say('PACKAGE INDEX case ' + index.str() + ' review')
	mut review := service.review('upgrade', [])!
	assert review.rows.len == 1 && review.rows[0].action == 'keep'
	review.close()
	os.write_file(workspace + '/index.json', text)!
	os.write_file(workspace + '/index.sig', original_signature)!
}
