// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module platformfixture

@[export:'main']
pub fn native_main() i32 {
	result := fixture_main()
	$if wifi_fixture_guest ? {
		C.fflush(nil)
		for { C.pause() }
	}
	return result
}
