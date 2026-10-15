// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn audit_protocol_fixture(count int) DeploymentAudit {
	mut rows := []DeploymentAuditRow{cap: count}
	for i in 0 .. count {
		rows << DeploymentAuditRow{ id: 'app-' + (10000 + i).str(), status: 'changed',
			expected_version: '1.0.0', installed_version: '2.0.0', differences: ['requested', 'version'] }
	}
	return DeploymentAudit{ generation: 7, architecture: 'aarch64', deployment_sha256: 'a'.repeat(64), matches: false, rows: rows }
}

fn test_audit_protocol_requires_complete_typed_canonical_coherent_and_bounded_rows() {
	text := json2.encode(audit_protocol_fixture(32))
	mut decoded := decode_deployment_audit(text)!
	assert decoded.rows.len == 32 && !decoded.matches && decoded.generation == 7
	decoded.close(); decoded.close()
	for bad in [text + '{}', text[..text.len - 1], text.replace('"format":1', '"format":2'),
		text.replace('"format":1', '"format":true'), text.replace('"generation":7', '"generation":-1'),
		text.replace('"generation":7', '"generation":07'), text.replace('"generation":7', '"generation":0'),
		text.replace('"generation":7', '"generation":18446744073709551616'),
		text.replace('"architecture":"aarch64"', '"architecture":null'),
		text.replace('"format":1', '"format":1,"extra":{}'), text.replace('"format":1', '"format":1,"forma\\u0074":1'),
		text.replace('"matches":false', '"matches":true'), text.replace('"matches":false', '"matches":0'),
		text.replace('"status":"changed"', '"status":"trusted"'), text.replace('"status":"changed"', '"status":"match"'),
		text.replace('"status":"changed"', '"status":"missing"'), text.replace('"status":"changed"', '"status":"unexpected"'),
		text.replace('"status":"changed"', '"status":"changed","stat\\u0075s":"changed"'),
		text.replace('app-10001', 'app-10000'), text.replace('app-10001', 'app-09999'),
		text.replace('app-10000', 'a'.repeat(129)), text.replace('app-10000', 'bad\\nname'), text.replace('app-10000', '\xff'),
		text.replace('"requested","version"', '"version","requested"'), text.replace('"requested","version"', '"version","version"'),
		text.replace('"requested","version"', '"health","version"'), text.replace('"requested","version"', '"requested"'),
		text.replace('"expected_version":"1.0.0"', '"expected_version":"2.0.0"'),
		text.replace('"installed_version":"2.0.0"', '"installed_version":""'),
		text.replace(',"differences":["requested","version"]', ''),
		text.replace('"rows":[', '"rows":null,"ignored":[')] {
		mut refused := false
		decode_deployment_audit(bad) or { refused = true; message := err.msg(); unsafe { message.free(); err.free() } }
		assert refused
	}
	mut empty := decode_deployment_audit('{"format":1,"generation":0,"architecture":"x86_64","deployment_sha256":"' + 'a'.repeat(64) + '","matches":true,"rows":[]}')!
	empty.close()
	maximum := json2.encode(audit_protocol_fixture(8192)); assert maximum.len < 8 * 1024 * 1024
	mut wide := decode_deployment_audit(maximum)!; assert wide.rows.len == 8192; wide.close()
	if _ := decode_deployment_audit(json2.encode(audit_protocol_fixture(8193))) { assert false }
	println('DEPLOYMENT AUDIT PROTOCOL complete typed fields, duplicate/unknown keys, bounded sorted union rows and coherent drift result PASS')
	$if track_heap ? {
		bad := text[..text.len - 1] + ',"extra":{}}'
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut report := decode_deployment_audit(text)!; report.close()
			decode_deployment_audit(bad) or { message := err.msg(); unsafe { message.free(); err.free() } }
		}
		kept := C.vinix_heap_end(); assert kept == 0, 'deployment audit decoder retained ${kept} bytes'
		println('DEPLOYMENT AUDIT PROTOCOL 1000 complete and partial-invalid decode/close cycles retain zero tracked bytes PASS')
	}
}
