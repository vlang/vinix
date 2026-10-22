// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

fn test_capabilities_match_real_signed_index_and_sdk_window_admission() {
	mut supported := capabilities()
	defer { supported.close() }
	supported.validate()!
	for format in 0 .. 4 {
		text := canonical_index(Index{ format: format, repository: 'fixture', sequence: 1, expires: 2000000000 })!
		defer { unsafe { text.free() } }
		mut accepted := false
		if index := decode_signed_index('fixture', text, 1) {
			accepted = true
			close_decoded_index(index)
		} else { unsafe { err.free() } }
		assert accepted == (format in supported.package_formats)
	}
	for architecture in ['aarch64', 'x86_64']! {
		for sdk in 0 .. 4 {
			for protocol in 0 .. 4 {
				package := Package{ id: 'fixture', name: 'Fixture', version: '1.0.0', architecture: architecture,
					kind: 'native', license: 'MIT', entrypoint: 'bin/fixture', sdk: sdk, window_protocol: protocol,
					permissions: ['display'], files: [Payload{ path: 'bin/fixture', bytes: 1,
						sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', executable: true }] }
				mut accepted := true
				package.validate() or { accepted = false; unsafe { err.free() } }
				assert accepted == supported.supports_package(1, sdk, protocol)
				unsafe { (&array(&package.permissions)).free(); (&array(&package.files)).free() }
			}
		}
	}
}

fn test_capabilities_match_deployment_parser_schema_gates() {
	mut supported := capabilities()
	defer { supported.close() }
	for format in 0 .. 4 {
		text := '{"format":' + format.str() + ',"architecture":"aarch64","packages":[]' +
			if format == 2 { ',"locked":[]}' } else { '}' }
		mut accepted := false
		if mut document := pkgprotocol.decode_deployment_document(text) {
			accepted = true
			document.close()
		} else { unsafe { err.free() } }
		assert accepted == (format in supported.deployment_formats)
		unsafe { text.free() }
	}
}
