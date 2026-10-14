// SPDX-License-Identifier: MIT
module appsdk

// SDK 1 grants form a bounded set. Repetition cannot add access and must not
// produce metadata that installs successfully but fails its launch context.
pub fn valid_permissions(values []string) bool {
	if values.len > grants.len { return false }
	for i, value in values {
		if value !in grants { return false }
		for j in 0 .. i { if values[j] == value { return false } }
	}
	return true
}
