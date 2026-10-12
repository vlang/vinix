// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn test_progress_has_bounded_typed_counters_and_owned_decoded_fields() {
	valid := Progress{ phase: 'download', package: 'app', repository: 'trusted', path: 'bin/app', current: 64, total: 128 }
	mut decoded := decode_progress(json2.encode(valid))!
	assert decoded == valid
	decoded.close()
	assert decoded.phase == '' && decoded.package == '' && decoded.path == ''
	for bad in [Progress{ ...valid, format: 2 }, Progress{ ...valid, phase: 'run' },
		Progress{ ...valid, current: 129 }, Progress{ ...valid, package: 'bad;command' },
		Progress{ ...valid, path: '../private' }, Progress{ ...valid, path: 'bin\napp' },
		Progress{ ...valid, total: u64(4) * 1024 * 1024 * 1024 + 1 },
		Progress{ ...valid, phase: 'activate' }, Progress{ phase: 'complete' },
		Progress{ phase: 'stage', total: 4097 }, Progress{ phase: 'metadata', repository: 'trusted', total: 1 }] {
		mut refused := false
		decode_progress(json2.encode(bad)) or { refused = true }
		assert refused
	}
	text := json2.encode(valid)
	for bad in [text.replace('"current":64,', ''), text.replace('"current":64', '"current":"64"'),
		text.replace('"current":64', '"current":null'), text.replace('"current":64', '"current":-1'),
		text.replace('"current":64', '"current":18446744073709551616'), ' '.repeat(progress_limit + 1)] {
		mut refused := false
		decode_progress(bad) or { refused = true }
		assert refused
	}
	for event in [Progress{ phase: 'resolve' }, Progress{ phase: 'verify', package: 'app', path: 'bin/app' },
		Progress{ phase: 'metadata', repository: 'trusted', path: 'index.json', current: 256 },
		Progress{ phase: 'stage', current: 2, total: 2 }, Progress{ phase: 'activate' },
		Progress{ phase: 'complete', current: 1, total: 1 }] { event.validate()! }
}
