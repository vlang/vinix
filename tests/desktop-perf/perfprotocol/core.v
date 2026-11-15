// SPDX-License-Identifier: GPL-2.0-or-later
// Normalize only the selected console's terminal CR sequence, never payload CR.
module perfprotocol

pub fn line(raw string) !string {
	mut end := raw.len
	$if perf_slab16k ? {
		if raw.ends_with('\r\r') { end -= 2 }
		else if raw.ends_with('\r') { end-- }
	} $else {
		if raw.ends_with('\r') { end-- }
	}
	for i in 0 .. end {
		if raw[i] < 32 || raw[i] > 126 { return error('non-ASCII or control byte in full heap protocol') }
	}
	return raw[..end]
}
