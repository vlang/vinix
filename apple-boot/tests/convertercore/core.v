// SPDX-License-Identifier: GPL-2.0-or-later
// Original independent host driver; buffers intentionally live until exit.
@[has_globals]
module convertercore
#include "converter-v-abi.h"
@[typedef] struct C.FILE {}
@[typedef] struct C.converter_ull {}
struct C.adt { base &u8 size usize }
struct C.fdt_builder {}
struct C.adt_fdt_extras { bootargs &char malformed_cells u32 }
@[c_extern] __global C.stderr &C.FILE
fn C.fopen(&char, &char) &C.FILE
fn C.fseek(&C.FILE, isize, i32) i32
fn C.ftell(&C.FILE) isize
fn C.fread(voidptr, usize, usize, &C.FILE) usize
fn C.fwrite(voidptr, usize, usize, &C.FILE) usize
fn C.fclose(&C.FILE) i32
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.fprintf(&C.FILE, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.fdt_begin(&C.fdt_builder, voidptr, usize, &char, usize, &u32, usize)
fn C.adt_to_fdt(&C.adt, &C.fdt_builder, &C.adt_fdt_extras) i32
fn C.fdt_finish(&C.fdt_builder) usize
fn C.adt_find_path(&C.adt, &char, &usize, &usize, usize) i32
fn C.adt_get_reg(&C.adt, &usize, usize, &u64, &u64) i32

fn read_file(path &char, size &usize) voidptr {
 unsafe {
  file := C.fopen(path, c'rb')
  if file == nil { return nil }
  C.fseek(file, 0, C.SEEK_END)
  length := usize(C.ftell(file))
  C.fseek(file, 0, C.SEEK_SET)
  data := C.malloc(length)
  if data == nil || C.fread(data, 1, length, file) != length {
   C.fclose(file)
   C.free(data)
   return nil
  }
  C.fclose(file)
  *size = length
  return data
 }
}
fn native_ull(value u64) C.converter_ull {
 mut result := C.converter_ull{}
 unsafe { C.memcpy(&result, &value, sizeof(u64)) }
 return result
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
 unsafe {
  if argc < 3 {
   C.fprintf(C.stderr, c'usage: %s ADT FDT [bootargs] [--reg PATH]...\n', argv[0])
   return 2
  }
  mut size := usize(0)
  blob := read_file(argv[1], &size)
  if blob == nil { C.fprintf(C.stderr, c'cannot read %s\n', argv[1]); return 1 }
  mut adt := C.adt{base: &u8(blob), size: size}
  capacity := size + (usize(1) << 20)
  buffer := C.malloc(capacity)
  strings := &char(C.malloc(usize(1) << 20))
  hash := &u32(C.malloc(sizeof(u32) << 16))
  mut builder := C.fdt_builder{}
  C.fdt_begin(&builder, buffer, capacity, strings, usize(1) << 20, hash, usize(1) << 16)
  mut extras := C.adt_fdt_extras{}
  mut argument := i32(3)
  if argc > 3 && C.strcmp(argv[3], c'--reg') != 0 { extras.bootargs = argv[3]; argument = 4 }
  if C.adt_to_fdt(&adt, &builder, &extras) != 0 { C.fprintf(C.stderr, c'conversion failed\n'); return 1 }
  total := C.fdt_finish(&builder)
  if total == 0 { C.fprintf(C.stderr, c'FDT overflowed\n'); return 1 }
  out := C.fopen(argv[2], c'wb')
  if out == nil || C.fwrite(buffer, 1, total, out) != total { C.fprintf(C.stderr, c'cannot write %s\n', argv[2]); return 1 }
  C.fclose(out)
  C.printf(c'adt %zu bytes -> fdt %zu bytes, malformed-cells %u\n', size, total, extras.malformed_cells)
  for ; argument + 1 < argc; argument += 2 {
   if C.strcmp(argv[argument], c'--reg') != 0 { break }
   mut node := usize(0)
   mut chain := [66]usize{}
   if C.adt_find_path(&adt, argv[argument + 1], &node, &chain[0], 66) != 0 {
    C.printf(c'reg %s: not found\n', argv[argument + 1])
    continue
   }
   for index := usize(0); ; index++ {
    mut address := u64(0)
    mut length := u64(0)
    if C.adt_get_reg(&adt, &chain[0], index, &address, &length) != 0 { break }
    C.printf(c'reg %s[%zu] 0x%llx 0x%llx\n', argv[argument + 1], index, native_ull(address), native_ull(length))
   }
  }
  return 0
 }
}
