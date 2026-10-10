// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

fn test_pending_oracles_keep_original_checks_and_source_lines() {
	source := original_source()!
	base, ported := base_sources(source)
	assert base.count('CHECK(') - base.count('#define CHECK(') == 76
	for span in base_ranges {
		assert base.contains('#line ' + span.first.str() + ' "test.c"\n')
		assert ported.contains('#line ' + (span.last + 1).str() + ' "test.c"\n')
	}
	for name in base_exports {
		assert !base.contains('static int ' + name + '(')
		assert base.contains('int ' + name + '(')
		assert !ported.contains('static int ' + name + '(')
	}
	assert ported.contains('#include <unistd.h>\n#include "basefixture-api.h"\n#line 51 "test.c"\n')
	assert rename_identifiers('reap_ok reap_ok2 _reap_ok *reap_ok(\n', ['reap_ok']) ==
		'original_reap_ok reap_ok2 _reap_ok *original_reap_ok(\n'
	futex := original_reference('futex', source, false)
	assert futex.count('CHECK(') - futex.count('#define CHECK(') == 5
	assert futex.contains('#line 1681 "test.c"\n')
	assert futex.contains('int original_test_futex_wake_op(')
	schema := source_schema('futex').as_map()
	value := schema['futex_lines'] or { panic('Missing futex line count') }
	assert value.int() == 18
}

fn test_futex_number_uses_numeric_target_definition_and_diagnostics_match_in_pairs() {
	assert parse_futex_number('#define SYS_other 2\n#define SYS_futex 98\n')! == '98'
	for text in ['', '#define SYS_futex (-1)', '#define SYS_futex 98x', '#define SYS_futex  98'] {
		if _ := parse_futex_number(text) {
			assert false
		}
	}
	mut rows := []string{}
	for i in 0 .. 7 { rows << [i.str(), i.str()] }
	rows << 'QEMU CORE FUTEX DIFFERENTIAL PASS'
	validate_futex_observations(rows.join('\n') + '\n')!
	for bad in [rows[..14].join('\n'), rows.join('\n') + '\nextra',
		rows.join('\n').replace_once('0\n', 'wrong\n')] {
		if _ := validate_futex_observations(bad) {
			assert false
		}
	}
}
