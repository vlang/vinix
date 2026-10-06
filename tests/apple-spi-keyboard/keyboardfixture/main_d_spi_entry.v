// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module keyboardfixture

fn C.pause() i32
fn C.vsf_reference_entry() i32

@[export: 'main']
pub fn entry() i32 {
 result := i32(0)
 $if spi_reference ? { result = C.vsf_reference_entry() } $else { result = suite() }
 $if spi_guest ? { unsafe { C.fflush(nil) }; for { C.pause() } }
 return result
}
