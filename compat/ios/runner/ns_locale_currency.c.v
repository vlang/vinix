// SPDX-License-Identifier: GPL-2.0-or-later
module main

// NSLocale and CFLocale export the same NSString key cell. Currency-value
// queries retain their explicit unsupported diagnostic in cf_locale_value.
fn ns_locale_currency_symbol(symbol string) ?u64 {
	if symbol !in ['_NSLocaleCurrencyCode', '_kCFLocaleCurrencyCode']! { return none }
	return ns_locale_key_cell(1)
}
