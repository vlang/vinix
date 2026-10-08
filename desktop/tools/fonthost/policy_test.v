// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
module fonthost

import fixturehost
import hosttest
import json2
import math.big
import os

fn test_rounding_keeps_ties_sign_and_arbitrary_integer_tokens() ! {
	for raw, expected in {'-5.5': '-6', '-4.5': '-4', '-0.5': '0', '0.5': '0', '1.5': '2', '2.5': '2', '7.5': '8', '9223372036854775808.0': '9223372036854775808'} {
		assert rounded(json2.Any({'float': json2.Any(raw)}))!.str() == expected
	}
	wide := '1' + '0'.repeat(200)
	assert rounded(json2.Any({'integer': json2.Any(wide)}))!.str() == wide
	for raw, expected in {'nan': 'ValueError', 'inf': 'OverflowError', '-inf': 'OverflowError'} {
		rounded(json2.Any({'float': json2.Any(raw)})) or {
			assert err is FontError
			if err is FontError { assert err.kind == expected }
			continue
		}
		assert false
	}
}

fn test_text_boundaries_and_python_floor_division() ! {
	assert wrap('中🙂e\u0301', 2)! == ['中🙂', 'e\u0301']
	assert wrap('\xed\xa0\x80x\xed\xbf\xbf', 1)! == ['\xed\xa0\x80', 'x', '\xed\xbf\xbf']
	assert wrap('abc', -1)! == []string{}
    assert split_lines('a\r\nb' + rune(0x85).str() + 'c' + rune(0x2028).str() + 'd' + rune(0x2029).str()) == ['a', 'b', 'c', 'd']
	assert strip_space('\u2000\x1c中\u3000') == '中'
	assert floor_half(big.integer_from_int(-3)).str() == '-2'
	assert floor_half(big.integer_from_int(3)).str() == '1'
}

fn test_catalog_reads_keep_utf8_newlines_and_value_only_coverage() ! {
	directory := hosttest.work_dir('', 'font-catalog-')!
	defer { hosttest.remove_work_dir(directory) or {} }
	path := directory + '/catalog.tr'
    fixturehost.write(path, ' ignored key \r\n中\u2000の' + rune(0x85).str() + '🙂\r\n-----\r\nempty')!
	assert catalog_runes([path])! == [0x306e, 0x4e2d, 0x1f642]
	fixturehost.write(path, 'key\n\xe2\x82')!
	catalog_runes([path]) or {
		assert err is hosttest.ModuleDecodeError
		if err is hosttest.ModuleDecodeError { assert err.start == 4 && err.end == 6 && err.reason == 'unexpected end of data' }
		return
	}
	assert false
}

fn test_repeated_source_errors_close_file_descriptors() ! {
	directory := hosttest.work_dir('', 'font-errors-')!
	defer { hosttest.remove_work_dir(directory) or {} }
	path := directory + '/source.tr'
	fixturehost.write(path, '\xff')!
	before := os.ls('/dev/fd')!
	for _ in 0 .. 100 {
		catalog_runes([path]) or { assert err is hosttest.ModuleDecodeError; continue }
		assert false
	}
	assert os.ls('/dev/fd')! == before
}
