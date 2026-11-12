// SPDX-License-Identifier: GPL-2.0-or-later
// Locate direct interface implementations without disassembling an entire APK.
module main

import encoding.binary
import os

fn word(data []u8, at u64) !u32 {
 if at > u64(data.len) || u64(data.len) - at < 4 { return error('truncated DEX word') }
 return binary.little_endian_u32(data[int(at)..int(at)+4])
}

fn descriptor(data []u8, id u32) !string {
 if id >= word(data, 64)! { return error('invalid type index') }
 strings := u64(word(data, 60)!)
 types := u64(word(data, 68)!)
 name := word(data, types + u64(id) * 4)!
 if name >= word(data, 56)! { return error('invalid string index') }
 mut cursor := u64(word(data, strings + u64(name) * 4)!)
 mut terminated := false
 for _ in 0 .. 5 {
  if cursor >= u64(data.len) { return error('truncated string length') }
  byte := data[int(cursor)]
  cursor++
  if byte & 0x80 == 0 { terminated = true; break }
 }
 if !terminated { return error('invalid string length') }
 start := int(cursor)
 for cursor < u64(data.len) && cursor - u64(start) <= 4096 {
  if data[int(cursor)] == 0 { return data[start..int(cursor)].bytestr() }
  if data[int(cursor)] > 127 { return error('non-ASCII descriptor') }
  cursor++
 }
 return error('unterminated descriptor')
}

fn inspect(path string, target string) ! {
 if os.file_size(path) > 16 * 1024 * 1024 { return error('DEX exceeds input limit') }
 data := os.read_bytes(path)!
 if data.len < 112 || data[..4].bytestr() != 'dex\n' || data[7] != 0
  || word(data, 32)! != data.len || word(data, 36)! != 112
  || word(data, 40)! != 0x12345678 { return error('unsupported DEX header') }
 count := u64(word(data, 96)!)
 table := u64(word(data, 100)!)
 if table + count * 32 > u64(data.len) { return error('truncated class table') }
 for i := u64(0); i < count; i++ {
  at := table + i * 32
  interfaces := u64(word(data, at + 12)!)
  if interfaces == 0 { continue }
  length := u64(word(data, interfaces)!)
  if interfaces + 4 + length * 2 > u64(data.len) { return error('truncated interface list') }
  for j := u64(0); j < length; j++ {
   pos := int(interfaces + 4 + j * 2)
   id := binary.little_endian_u16(data[pos..pos+2])
   if descriptor(data, u32(id))! == target {
    println(path + ' ' + descriptor(data, word(data, at)!)!)
   }
  }
 }
}

fn main() {
 if os.args.len < 3 { panic('usage: maps-dex-interfaces DESCRIPTOR DEX...') }
 for path in os.args[2..] { inspect(path, os.args[1])! }
}
