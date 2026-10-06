// SPDX-License-Identifier: ISC
@[translated]
module ctlfixture

@[export:'main']
pub fn main_entry(argc i32, argv &&char) i32 {
	$if wifi_fixture_guest ? {
		return guest_main()
	} $else {
		return fixture_main(argc, argv)
	}
}
