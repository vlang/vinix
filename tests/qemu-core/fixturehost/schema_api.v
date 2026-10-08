// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import json2

// Share the qualified original two-space, ASCII-escaped receipt formatting.
pub fn write_receipt(path string, value json2.Any) ! {
	write_schema(path, value)!
}
