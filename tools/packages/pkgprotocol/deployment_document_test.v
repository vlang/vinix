// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

fn test_deployment_wire_documents_own_fields_and_require_the_exact_versioned_shape() {
	mut source := '{"locked":[{"id":"app","version":"1.0.0","architecture":"all","repository":"publisher","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","minimum_sequence":18446744073709551615,"metadata_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}],"packages":["app"],"architecture":"x86_64","format":2}'.clone()
	mut document := decode_deployment_document(source)!
	unsafe { source.free() }
	assert document.format == 2 && document.architecture == 'x86_64' && document.packages == ['app']
	assert document.locked[0].repository == 'publisher' && document.locked[0].minimum_sequence == ~u64(0)
	document.close(); document.close()
	assert document.packages.len == 0 && document.locked.len == 0 && document.architecture == ''
	mut roots := decode_deployment_document('{"format":1,"architecture":"aarch64","packages":[]}')!
	assert roots.format == 1 && roots.locked.len == 0; roots.close()
	for text in ['{"format":1,"architecture":"aarch64","packages":[],"locked":[]}',
		'{"format":2,"architecture":"x86_64","packages":[]}',
		'{"format":2,"architecture":"x86_64","packages":[],"locked":null}',
		'{"format":2,"architecture":"x86_64","packages":[],"locked":[] ,"forma\\u0074":2}',
		'{"format":2,"architecture":"x86_64","packages":[],"locked":[{"id":"app"}]}'] {
		if mut value := decode_deployment_document(text) { value.close(); assert false } else { unsafe { err.free() } }
	}
	println('Deployment document protocol: owned strings, repeatable close, full-width sequence, formats 1/2 and exact required schema PASS')
}
