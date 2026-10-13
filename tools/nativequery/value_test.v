// SPDX-License-Identifier: GPL-2.0-or-later
module nativequery

import json2

fn test_numeric_tokens_keep_width_and_spelling() ! {
	for token in ['18446744073709551615', '-9223372036854775809', '1' + '0'.repeat(200), '1.2500e+300',
		'-0'] {
		decoded := json2.decode[Value]('{"number":' + token + '}')!
		assert encode(decoded) == '{"number":' + token + '}'
	}
}

fn test_saved_error_index_is_an_integer() ! {
	for token in ['0', '27', '-1'] {
		assert binding_index(json2.decode[Value](token)!)! == token.int()
	}
	for token in ['0.0', 'true', '"0"', 'null', '18446744073709551615'] {
		binding_index(json2.decode[Value](token)!) or { continue }
		assert false, token
	}
}
