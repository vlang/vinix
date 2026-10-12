// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct JsonFailure {
	reason string
}

fn (failure &JsonFailure) msg() string { return failure.reason }

fn (failure &JsonFailure) code() int { return 3840 }

const json_failures = [
	JsonFailure{ reason: 'Invalid Unicode scalar' },
	JsonFailure{ reason: 'JSON text exceeds size limit' },
	JsonFailure{ reason: 'Invalid UTF-8 JSON' },
	JsonFailure{ reason: 'Truncated Unicode JSON' },
	JsonFailure{ reason: 'Missing Unicode surrogate' },
	JsonFailure{ reason: 'Invalid Unicode surrogate' },
	JsonFailure{ reason: 'Truncated Unicode escape' },
	JsonFailure{ reason: 'Invalid Unicode escape' },
	JsonFailure{ reason: 'Expected JSON string' },
	JsonFailure{ reason: 'Unescaped control character' },
	JsonFailure{ reason: 'Truncated JSON escape' },
	JsonFailure{ reason: 'Invalid JSON escape' },
	JsonFailure{ reason: 'Unterminated JSON string' },
	JsonFailure{ reason: 'Missing JSON number' },
	JsonFailure{ reason: 'Invalid JSON number' },
	JsonFailure{ reason: 'Missing fractional digits' },
	JsonFailure{ reason: 'Missing exponent digits' },
	JsonFailure{ reason: 'JSON decimal precision profile exceeded' },
	JsonFailure{ reason: 'Non-finite JSON number' },
	JsonFailure{ reason: 'JSON integer exceeds 64-bit profile' },
	JsonFailure{ reason: 'JSON integer exceeds signed 64-bit profile' },
	JsonFailure{ reason: 'JSON nesting or node limit exceeded' },
	JsonFailure{ reason: 'Unexpected end of JSON' },
	JsonFailure{ reason: 'Unexpected JSON token' },
	JsonFailure{ reason: 'Missing JSON colon' },
	JsonFailure{ reason: 'Missing JSON comma' },
	JsonFailure{ reason: 'Unreachable JSON parser state' },
	JsonFailure{ reason: 'Mutable JSON leaves and extended reading options are not implemented' },
	JsonFailure{ reason: 'JSON input must be NSData' },
	JsonFailure{ reason: 'JSON input exceeds size limit' },
	JsonFailure{ reason: 'Trailing JSON data' },
	JsonFailure{ reason: 'JSON fragments require the fragments option' },
	JsonFailure{ reason: 'JSON output exceeds size limit' },
	JsonFailure{ reason: 'Invalid UTF-8 JSON string' },
	JsonFailure{ reason: 'Unsupported JSON object type' },
	JsonFailure{ reason: 'Cyclic JSON collection' },
	JsonFailure{ reason: 'Unsupported raw JSON collection' },
	JsonFailure{ reason: 'Invalid JSON dictionary' },
	JsonFailure{ reason: 'JSON dictionary keys must be strings' },
	JsonFailure{ reason: 'Sorted JSON key collation is outside the ASCII profile' },
	JsonFailure{ reason: 'JSON writing options are not implemented' },
]!

// Error interfaces reference these process-lifetime records, avoiding a
// heap-allocated MessageError on every malformed request.
fn json_failure(reason string) IError {
	for i in 0 .. json_failures.len {
		if json_failures[i].reason == reason { return unsafe { &json_failures[i] } }
	}
	return unsafe { &json_failures[0] }
}
