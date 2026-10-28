// SPDX-License-Identifier: GPL-2.0-or-later
module accounthandoff

fn test_handoff_finite_schema_and_canonical_parser() {
	mut accepted := 0
	for stage in 1 .. 14 {
		for operation in [2, 3, 4] {
			for event in 0 .. 3 {
				for code in [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9] {
					text := 'ANDROID-ACCOUNT-HANDOFF stage=${stage} operation=${operation} event=${event} code=${code}'
					expected := if stage == 9 {
						(event == 1 && code == 0) || (event == 2 && code != 0)
					} else {
						event == 0 && code == 0 && (stage == 1 || operation != 3)
					}
					mut parsed := false
					if record := parse_handoff_diagnostic(text) {
						parsed = true
						assert record == HandoffDiagnostic{stage, operation, event, code}
						accepted++
					}
					assert parsed == expected, text
				}
			}
		}
	}
	assert accepted == 58
}

fn test_handoff_parser_rejects_noncanonical_private_or_extension_data() {
	valid := 'ANDROID-ACCOUNT-HANDOFF stage=9 operation=2 event=2 code=6'
	for text in [
		valid + ' request=123', valid + ' private@example.test', valid + '\n',
		' ' + valid, valid + ' ', valid.replace(' stage=', '  stage='),
		valid.replace('stage=9', 'stage=09'), valid.replace('stage=9', 'stage=+9'),
		valid.replace('stage=9', 'stage=0'), valid.replace('stage=9', 'stage=14'),
		valid.replace('operation=2', 'operation=1'), valid.replace('operation=2', 'operation=5'),
		valid.replace('event=2', 'event=4'), valid.replace('code=6', 'code=0'),
		valid.replace('code=6', 'code=10'), valid.replace('code=6', 'code=-2'),
		valid.replace('code=6', 'code=-'), valid.replace('code=6', 'code=-0'),
		valid.replace('code=6', 'code=-01'), valid.replace('code=6', 'code='),
		valid.replace('code=6', 'code=06'), valid.replace('code=6', 'code=+6'),
		valid.replace('code=6', 'code=2147483648'), valid.replace('code=6', 'code=private@example.test'),
		valid.replace('code=6', 'code=6\x00'), valid.replace('code=6', 'code=6\t'),
		valid.replace('event=2 code=6', 'code=6 event=2'), 'x'.repeat(97), '',
	] {
		parse_handoff_diagnostic(text) or {
			assert err.msg() == 'invalid account handoff diagnostic'
			continue
		}
		assert false, 'unexpected diagnostic accepted'
	}
}
