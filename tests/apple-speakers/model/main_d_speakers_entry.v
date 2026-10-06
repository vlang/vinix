// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module model

@[export: 'main']
pub fn native_main() i32 {
	result := fixture_main()
	$if speakers_guest ? {
		C.fflush(voidptr(0))
		for { C.pause() }
	}
	return result
}
