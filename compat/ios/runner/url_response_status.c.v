// SPDX-License-Identifier: GPL-2.0-or-later
module main

// English status strings measured on installed Foundation; no transport.
fn response_status_text(status i64) string {
	return match status {
		100 { 'continue' }
		101 { 'switching protocols' }
		200 { 'no error' }
		201 { 'created' }
		202 { 'accepted' }
		203 { 'non-authoritative information' }
		204 { 'no content' }
		205 { 'reset content' }
		206 { 'partial content' }
		300 { 'multiple choices' }
		301 { 'moved permanently' }
		302 { 'found' }
		303 { 'see other' }
		304 { 'not modified' }
		305 { 'needs proxy' }
		307 { 'temporarily redirected' }
		400 { 'bad request' }
		401 { 'unauthorized' }
		402 { 'payment required' }
		403 { 'forbidden' }
		404 { 'not found' }
		405 { 'method not allowed' }
		406 { 'unacceptable' }
		407 { 'proxy authentication required' }
		408 { 'request timed out' }
		409 { 'conflict' }
		410 { 'no longer exists' }
		411 { 'length required' }
		412 { 'precondition failed' }
		413 { 'request too large' }
		414 { 'requested URL too long' }
		415 { 'unsupported media type' }
		416 { 'requested range not satisfiable' }
		417 { 'expectation failed' }
		500 { 'internal server error' }
		501 { 'unimplemented' }
		502 { 'bad gateway' }
		503 { 'service unavailable' }
		504 { 'gateway timed out' }
		505 { 'unsupported version' }
		else { if status >= 100 && status < 200 { 'informational' } else if status >= 200 && status < 300 { 'success' } else if status >= 300 && status < 400 { 'redirected' } else if status >= 400 && status < 500 { 'client error' } else { 'server error' } }
	}
}
