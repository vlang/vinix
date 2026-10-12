// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

// Guest-agent data follows base64.b64decode's ASCII, padding and ignored-byte
// policy. V's unchecked decoder also accepts truncated input, so own validation
// and decoding here. Reference: CPython v3.10.19 Modules/binascii.c a2b_base64.
pub fn decode_base64(text string) ![]u8 {
 if text.bytes().any(it >= 128) { return error('base64 input must be ASCII') }
 alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
 values := alphabet.bytes()
 mut result := []u8{}; mut bits := 0; mut partial := u32(0); mut count := 0; mut padding := 0
 for byte in text.bytes() {
  if byte == `=` {
   if count % 4 >= 2 { padding++; if count % 4 + padding >= 4 { return result } }
   continue
  }
  at := values.index(byte)
  if at < 0 { continue }
  padding = 0; count++
  partial = (partial << 6) | u32(at); bits += 6
  if bits >= 8 { bits -= 8; result << u8(partial >> bits); partial &= (u32(1) << bits) - 1 }
 }
 if count % 4 != 0 { return error('invalid base64 length or padding') }
 return result
}
