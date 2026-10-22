// SPDX-License-Identifier: GPL-2.0-or-later
module smb2

// A successful final SPNEGO response must accept the selected mechanism, not
// request another exchange. Mechanism-list MIC negotiation is not implemented.
fn spnego_complete(p &u8, length int) bool {
	_, token_length := spnego_token(p, length) or { return false }
	if token_length != 0 { return false }
	_, outer, _, outer_end := der_element(p, length, 0) or { return false }
	_, sequence, _, sequence_end := der_element(p, outer_end, outer) or { return false }
	mut at := sequence
	mut accepted := false
	for at < sequence_end {
		tag, body, _, next := der_element(p, sequence_end, at) or { return false }
		if tag == 0xa3 { return false }
		if tag == 0xa0 {
			_, data, size, _ := der_element(p, next, body) or { return false }
			if size != 1 || unsafe { p[data] } != 0 { return false }
			accepted = true
		}
		at = next
	}
	return accepted
}
