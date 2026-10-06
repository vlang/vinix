// SPDX-License-Identifier: ISC
@[translated]
module protocolfixture

@[export:'main']
pub fn native_main() i32 {
	result := fixture_main()
	$if wifi_fixture_guest ? {
		C.fflush(voidptr(0))
		for { C.pause() }
	}
	return result
}
