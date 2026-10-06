// SPDX-License-Identifier: GPL-2.0-or-later
// Original independent native boot ABI and page-table golden fixture.
@[has_globals]
module bootfixture
#include "boot-fixture-v-abi.h"
struct C.boot_info { revision u16 version u16 devtree u64 cmdline &char boot_flags u64 mem_size_actual u64 }
struct C.allocator { start u64 next u64 end u64 }
struct C.pagemap { root u64 }
struct Segment { virt u64 bytes u64 flags u32 }
struct C.loaded_kernel { entry u64 phys_base u64 bytes u64 segment_count u32 segments [16]Segment }
struct Range { base u64 end u64 }
struct C.reserved_set { ranges [48]Range count u32 }
struct C.memmap_entry { base u64 length u64 @type u64 }
struct C.memmap { entries [64]C.memmap_entry count u32 }
fn C.assert(bool)
@[noreturn]
fn C.abort()
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.free(voidptr)
fn C.puts(&char) i32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.parse_boot_args(u64, &C.boot_info) i32
fn C.applecore__tcr_value() u64
fn C.alloc_zeroed(&C.allocator, u64, u64) u64
fn C.pagemap_init(&C.pagemap, &C.allocator)
fn C.map_range(&C.pagemap, u64, u64, u64, u32, u32)
fn C.load_elf(&u8, u64, &C.allocator, &C.loaded_kernel) i32
fn C.reserved_window(&C.reserved_set, u64, u64, u64, u64) u64
fn C.memmap_add(&C.memmap, u64, u64, u64, &C.reserved_set)
fn C.memmap_add_reserved(&C.memmap, &C.reserved_set)

__global fixture_mmfr u64
@[export: 'loader_end'] __global fixture_end [8]char
@[export: 'read_id_aa64mmfr0'] pub fn read_mmfr() u64 { return fixture_mmfr }
@[export: 'read_current_el'] pub fn read_el() u64 { return 8 }
@[export: 'read_midr'] pub fn read_midr() u64 { return 0 }
@[export: 'cache_invalidate_range'] pub fn invalidate(a u64, b u64) {}
@[export: 'quiesce_fiq_sources'] pub fn quiesce() {}
@[export: 'apple_mmio_write32'] pub fn mmio_write(address u64, value u32) {
 unsafe { C.__atomic_store_n(&u32(usize(address)), value, 0) }
}
@[export: 'halt_forever'; noreturn] pub fn halt() { C.abort() }
@[export: 'enter_kernel'; noreturn] pub fn enter(a u64, b u64, c u64, d u64, e u64, f u64, g u64) { C.abort() }

fn put32(p &u8, value u32) { unsafe { for i := u32(0); i < 4; i++ { p[i] = u8(value >> (i * 8)) } } }
fn put64(p &u8, value u64) { unsafe { for i := u32(0); i < 8; i++ { p[i] = u8(value >> (i * 8)) } } }

@[export: 'main']
pub fn run() i32 {
 unsafe {
  for revision := u32(1); revision <= 4; revision++ {
   mut args := [1200]u8{}
   mut info := C.boot_info{}
   lengths := [u32(0), u32(256), u32(608), u32(1024)]!
   args[0] = u8(revision)
   args[2] = 2
   put64(&args[0] + 8, 0xfffffe0000000000)
   put64(&args[0] + 16, 0x40000000)
   put64(&args[0] + 24, 0x80000000)
   put64(&args[0] + 32, 0x41000000)
   put64(&args[0] + 96, 0xfffffe0001000000)
   put32(&args[0] + 104, 2048)
   C.memcpy(&args[0] + 108, c'fixture', 8)
   tail := (u32(108) + lengths[if revision < 3 { revision } else { u32(3) }] + 7) & ~u32(7)
   put64(&args[0] + tail, 0x123456789abcdef0)
   put64(&args[0] + tail + 8, 0x90000000)
   C.assert(C.parse_boot_args(u64(usize(&args[0])), &info) == 0)
   C.assert(info.revision == revision && info.version == 2 && info.devtree == 0x41000000)
   C.assert(usize(info.cmdline) == usize(&args[0]) + 108 && info.boot_flags == 0x123456789abcdef0 && info.mem_size_actual == 0x90000000)
   args[0] = 0
   C.assert(C.parse_boot_args(u64(usize(&args[0])), &info) < 0)
  }
  for fixture_mmfr = 0; fixture_mmfr < 16; fixture_mmfr++ {
   wanted := ((if fixture_mmfr > 5 { u64(5) } else { fixture_mmfr }) << 32) | (u64(2) << 30) | (u64(3) << 28) | (u64(1) << 26) | (u64(1) << 24) | (u64(16) << 16) | (u64(3) << 12) | (u64(1) << 10) | (u64(1) << 8) | u64(16)
   C.assert(C.applecore__tcr_value() == wanted)
  }
  @[freed]
  mut pool := voidptr(nil)
  C.assert(C.posix_memalign(&pool, 0x200000, 0x800000) == 0)
  C.memset(pool, 0xa5, 0x800000)
  mut allocator := C.allocator{start: u64(usize(pool)), next: u64(usize(pool)), end: u64(usize(pool)) + 0x800000}
  zero := C.alloc_zeroed(&allocator, 3, 1)
  C.assert(zero == u64(usize(pool)) && allocator.next == zero + 0x4000)
  for i := u32(0); i < 0x4000; i++ { C.assert((&u8(pool))[i] == 0) }
  mut page_map := C.pagemap{}
  C.pagemap_init(&page_map, &allocator)
  C.map_range(&page_map, 0, 0, 0x40000000, C.PTE_ATTR_DEVICE, C.MAP_WRITE)
  l0 := &u64(usize(page_map.root))
  l1 := &u64(usize(l0[0] & u64(0x0000fffffffff000)))
  C.assert(l1[0] == (u64(1) << 54) | (u64(1) << 53) | (u64(1) << 10) | (u64(2) << 2) | u64(1))
  C.map_range(&page_map, 0x80000000, 0x60000000, 0x200000, C.PTE_ATTR_NORMAL, C.MAP_WRITE | C.MAP_EXEC)
  mut l2 := &u64(usize(l1[2] & u64(0x0000fffffffff000)))
  C.assert(l2[0] == u64(0x60000000) | (u64(1) << 54) | (u64(1) << 10) | (u64(3) << 8) | u64(1))
  C.map_range(&page_map, 0xc0001000, 0x50001000, 1, C.PTE_ATTR_FRAMEBUFFER, 0)
  l2 = &u64(usize(l1[3] & u64(0x0000fffffffff000)))
  l3 := &u64(usize(l2[0] & u64(0x0000fffffffff000)))
  C.assert(l3[1] == u64(0x50001000) | (u64(1) << 54) | (u64(1) << 53) | (u64(1) << 10) | (u64(3) << 8) | (u64(1) << 7) | (u64(1) << 2) | u64(3))
  mut image := [256]u8{}
  mut kernel := C.loaded_kernel{}
  C.memcpy(&image[0], c'\x7f\x45LF', 4)
  image[4] = 2
  image[5] = 1
  image[18] = 183
  put64(&image[0] + 24, 0xffffffff80000000)
  put64(&image[0] + 32, 64)
  image[54] = 56
  image[56] = 1
  put32(&image[0] + 64, 1)
  put32(&image[0] + 68, 3)
  put64(&image[0] + 72, 128)
  put64(&image[0] + 80, 0xffffffff80000000)
  put64(&image[0] + 96, 4)
  put64(&image[0] + 104, 8)
  C.memcpy(&image[0] + 128, c'ELF!', 4)
  C.assert(C.load_elf(&image[0], sizeof(image), &allocator, &kernel) == 0)
  C.assert(kernel.entry == 0xffffffff80000000 && kernel.bytes == 0x4000 && kernel.segment_count == 1 && kernel.segments[0].flags == C.MAP_WRITE | C.MAP_EXEC)
  C.assert(C.memcmp(voidptr(usize(kernel.phys_base)), c'ELF!\x00\x00\x00\x00', 8) == 0)
  image[4] = 1
  C.assert(C.load_elf(&image[0], sizeof(image), &allocator, &kernel) < 0)
  mut reserved := C.reserved_set{}
  reserved.ranges[0].base = 0x20000
  reserved.ranges[0].end = 0x30000
  reserved.ranges[1].base = 0x50000
  reserved.ranges[1].end = 0x60000
  reserved.count = 2
  C.assert(C.reserved_window(&reserved, 0x10000, 0x100000, 0x30000, 0x4000) == 0x60000)
  mut memmap := C.memmap{}
  C.memmap_add(&memmap, 0x10000, 0x70000, C.MEMMAP_USABLE, &reserved)
  C.memmap_add_reserved(&memmap, &reserved)
  C.assert(memmap.count == 5 && memmap.entries[0].base == 0x10000 && memmap.entries[0].length == 0x10000)
  C.assert(memmap.entries[1].base == 0x20000 && memmap.entries[1].@type == C.MEMMAP_RESERVED)
  C.assert(memmap.entries[4].base == 0x60000 && memmap.entries[4].length == 0x10000)
  C.free(pool)
  C.puts(c'Apple loader boot ABI/runtime: PASS')
  return 0
 }
}
