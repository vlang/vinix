// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated scanner qualification: no signing/key generation is invoked.
module pkgcore

import json2

const key_policy_fixture = '{"format":1,"architecture":"aarch64","policy":{"offline":false,"allowed":[],"pins":[{"id":"app","minimum":"1.0.0","before":"2.0.0"},{"id":"runtime","minimum":"","before":""}],"permissions":[],"licenses":["{\\\"offline\\\":true}","braces [] {} and \\\"quotes\\\""],"allow_firmware":false,"reserve_bytes":0}}'
const key_lock_fixture = '{"format":2,"architecture":"aarch64","packages":["app"],"locked":[{"id":"app","version":"1.0.0","architecture":"aarch64","repository":"publisher","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","minimum_sequence":1,"metadata_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"id":"runtime","version":"1.0.0","architecture":"aarch64","repository":"publisher","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","minimum_sequence":1,"metadata_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}]}'

fn test_document_key_scanner_tracks_siblings_arrays_escaped_keys_and_quoted_values() {
	for _ in 0 .. 100 {
		document_keys(key_policy_fixture, policy_document_field)!
		document_keys(key_policy_fixture.replace('"policy"', '"pol\\u0069cy"'), policy_document_field)!
		deployment_keys(key_lock_fixture, 2)!
		deployment_keys('{"format":1,"architecture":"aarch64","packages":[]}', 1)!
	}
	for invalid in [
		key_policy_fixture.replace('"offline":false', '"offline":true,"off\\u006cine":false'),
		key_policy_fixture.replace('"policy":{', '"policy":{"format":1,'),
		key_policy_fixture.replace('"id":"runtime"', '"id":"runtime","i\\u0064":"runtime"'),
		key_policy_fixture.replace('"minimum":"1.0.0"', '"minimum":"1.0.0","minimun":"1.0.0"'),
		key_policy_fixture.replace('"format":1', '"format":1,"future":{"policy":{"pins":[]}}'),
	] {
		// The structural pass is deliberately subsequent to successful decoding.
		json2.decode[PolicyFile](invalid, strict: true)!
		mut refused := false
		document_keys(invalid, policy_document_field) or { refused = err.msg().contains('document field') }
		assert refused, invalid
	}
	for invalid in [
		key_lock_fixture.replace('"version":"1.0.0"', '"version":"1.0.0","version":"1.0.0"'),
		key_lock_fixture.replace('"id":"runtime"', '"id":"runtime","permissions":[]'),
		key_lock_fixture.replace('"locked":', '"locked":[],"locked":'),
	] {
		json2.decode[DeploymentLockInput](invalid, strict: true)!
		mut refused := false
		deployment_keys(invalid, 2) or { refused = true }
		assert refused, invalid
	}
	println('Document scanner: sibling records, escaped keys, quoted values and repeated ownership retirement passed')
}
