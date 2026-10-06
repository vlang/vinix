// SPDX-License-Identifier: GPL-2.0-or-later
module ext2fixture
@[export: 'main']
pub fn fixture_main() i32 {
 result:=run()
 $if ans_fixture_guest ? { C.fflush(unsafe { nil }); for { C.pause() } }
 return result
}
