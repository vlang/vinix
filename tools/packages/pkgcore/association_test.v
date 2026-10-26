// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

fn association_package(value string) Package {
	return Package{id: 'editor', version: '1.0.0', architecture: 'all', kind: 'data',
		name: 'Editor', license: 'MIT', associations: [value],
		files: [Payload{path: 'share/data', sha256: 'a'.repeat(64), bytes: 1}]}
}

fn test_package_validation_refuses_malformed_associations_from_manifest_bytes() {
	for value in ['/', 'text/', '/plain', 'text/plain/extra', 'text/ plain', 'text/plain ',
		'text/pl\\ain', 'text/é', 'text/*', 'text/.plain', 'text/plain;charset=utf-8'] {
		p := association_package(value)
		// Round-trip through the actual manifest parser so JSON escape spellings
		// cannot evade the same admission used by signed package metadata.
		text := json2.encode(p)
		parsed := decode_manifest(text, false)!
		mut refused := false
		parsed.validate() or {
			message := err.msg()
			refused = message == 'editor: invalid MIME association'
			unsafe { message.free(); err.free() }
		}
		close_decoded_package(parsed)
		if !refused { panic('package admitted malformed MIME association') }
	}
}

fn test_package_association_identity_survives_manifest_and_launcher_generation() {
	for value in ['text/plain', 'application/vnd.example.editor+json', 'x-scheme-handler/https', 'Text/Plain'] {
		p := association_package(value)
		p.validate()!
		parsed := decode_manifest(json2.encode(p), false)!
		parsed.validate()!
		launcher := desktop_entry(parsed)
		if parsed.associations != [value] || !launcher.contains('MimeType=' + value + ';\n') {
			panic('package changed literal MIME identity')
		}
		close_decoded_package(parsed)
		unsafe { launcher.free() }
	}
}
