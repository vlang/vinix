// SPDX-License-Identifier: GPL-2.0-or-later
// Locate interface implementations or method references with a selected parameter.
module main

import encoding.binary
import os

fn word(data []u8, at u64) !u32 {
 if at > u64(data.len) || u64(data.len) - at < 4 { return error('truncated DEX word') }
 return binary.little_endian_u32(data[int(at)..int(at)+4])
}

fn descriptor(data []u8, id u32) !string {
 if id >= word(data, 64)! { return error('invalid type index') }
 types := u64(word(data, 68)!)
 name := word(data, types + u64(id) * 4)!
 return string_at(data, name)
}

fn string_at(data []u8, name u32) !string {
 strings := u64(word(data, 60)!)
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

fn inspect(path string, target string, parameter bool) ! {
 if os.file_size(path) > 16 * 1024 * 1024 { return error('DEX exceeds input limit') }
 data := os.read_bytes(path)!
 if data.len < 112 || data[..4].bytestr() != 'dex\n' || data[7] != 0
  || word(data, 32)! != data.len || word(data, 36)! != 112
  || word(data, 40)! != 0x12345678 { return error('unsupported DEX header') }
 count := u64(word(data, 96)!)
 table := u64(word(data, 100)!)
 if table + count * 32 > u64(data.len) { return error('truncated class table') }
 if parameter {
  methods, method_table := u64(word(data, 88)!), u64(word(data, 92)!)
  protos, proto_table := u64(word(data, 72)!), u64(word(data, 76)!)
  if method_table + methods * 8 > u64(data.len) || proto_table + protos * 12 > u64(data.len) {
   return error('truncated method/prototype table')
  }
  mut selected := u32(0xffffffff)
  for id := u32(0); id < word(data, 64)!; id++ {
   if descriptor(data, id)! == target { selected = id; break }
  }
  if selected == 0xffffffff { return }
  mut defined := map[u32]bool{}
  for i := u64(0); i < count; i++ { defined[word(data, table + i * 32)!] = true }
  for i := u64(0); i < methods; i++ {
   at := int(method_table + i * 8)
   owner := u32(binary.little_endian_u16(data[at..at+2]))
   if owner !in defined { continue }
   proto := u64(binary.little_endian_u16(data[at+2..at+4]))
   if proto >= protos { return error('invalid prototype index') }
   params := u64(word(data, proto_table + proto * 12 + 8)!)
   if params == 0 { continue }
   length := u64(word(data, params)!)
   if params + 4 + length * 2 > u64(data.len) { return error('truncated parameter list') }
   for j := u64(0); j < length; j++ {
    pos := int(params + 4 + j * 2)
    if u32(binary.little_endian_u16(data[pos..pos+2])) == selected {
     println(path + ' ' + descriptor(data, owner)! + '->' + string_at(data, word(data, u64(at+4))!)!)
     break
    }
   }
  }
  return
 }
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
 parameter := os.args.len >= 2 && os.args[1] == '--parameter'
 start := if parameter { 3 } else { 2 }
 if os.args.len <= start { panic('usage: maps-dex-interfaces [--parameter] DESCRIPTOR DEX...') }
 for path in os.args[start..] { inspect(path, os.args[start-1], parameter)! }
}
