// SPDX-License-Identifier: GPL-2.0-or-later
module probebudget

fn test_budget_config_rejects_unlimited_ambiguous_and_overflowing_values() {
	for text in ['', '0', 'max', '-4096', '+4096', '4096\n', ' 4096', '4G', '4097',
		'9223372036854775807', '9223372036854775808', '9223372036854779904',
		'18446744073709551616', '999999999999999999999999999'] {
		if value := parse(text) { assert false, '${text} accepted as ${value}' }
	}
	for text in ['4096', '67108864', '2147483648', '4294967296', '0004096', '9223372036854771712'] {
		assert (parse(text) or { panic('${text}: ${err}') }) == text.u64()
	}
}
