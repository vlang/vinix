// SPDX-License-Identifier: GPL-2.0-only
// The original native fixture's goldens and bounds call unchanged Linux helpers.
@[translated]
module i915policyfixture

#include "linuxkpi_i915_policy_v_contract.h"

fn C.intel_lookup_range_min_qp(i32, i32, i32, bool) u8
fn C.intel_lookup_range_max_qp(i32, i32, i32, bool) u8
fn C.MKDEV(u32, u32) u32
fn C.MAJOR(u32) u32
fn C.MINOR(u32) u32
fn C.new_encode_dev(u32) u32
fn C.new_decode_dev(u32) u32
fn C.huge_encode_dev(u32) u64
fn C.huge_decode_dev(u64) u32
fn C.old_valid_dev(u32) bool
fn C.old_encode_dev(u32) u16
fn C.old_decode_dev(u16) u32
fn C.sysv_valid_dev(u32) bool
fn C.sysv_encode_dev(u32) u32
fn C.sysv_major(u32) u32
fn C.sysv_minor(u32) u32
fn C.format_dev_t(&char, u32) &char
fn C.print_dev_t(&char, u32) i32
fn C.strcmp(&char, &char) i32
fn C.vinix_linuxkpi_irq_flags() u64
fn C.vinix_linuxkpi_preempt_count() u32
fn C.i915_fence_context_timeout(voidptr, u64) u64
fn C.i915_fence_timeout(voidptr) u64

struct QpGolden {
    bpc i32
    row i32
    column i32
    is_420 bool
    minimum u8
    maximum u8
}

const qp_goldens = [QpGolden{8, 0, 0, false, 0, 4}, QpGolden{8, 0, 36, false, 0, 0},
    QpGolden{8, 14, 0, false, 14, 15}, QpGolden{8, 14, 36, false, 3, 4},
    QpGolden{8, 3, 2, false, 2, 7}, QpGolden{8, 7, 18, false, 2, 4},
    QpGolden{8, 10, 34, false, 1, 2}, QpGolden{8, 13, 6, false, 7, 11},
    QpGolden{10, 0, 0, false, 0, 8}, QpGolden{10, 0, 48, false, 0, 0},
    QpGolden{10, 14, 0, false, 18, 19}, QpGolden{10, 14, 48, false, 3, 4},
    QpGolden{10, 3, 2, false, 6, 11}, QpGolden{10, 7, 24, false, 5, 7},
    QpGolden{10, 10, 46, false, 1, 2}, QpGolden{10, 13, 6, false, 12, 15},
    QpGolden{12, 0, 0, false, 0, 12}, QpGolden{12, 0, 60, false, 0, 0},
    QpGolden{12, 14, 0, false, 22, 23}, QpGolden{12, 14, 60, false, 3, 4},
    QpGolden{12, 3, 2, false, 10, 15}, QpGolden{12, 7, 30, false, 7, 8},
    QpGolden{12, 10, 58, false, 1, 2}, QpGolden{12, 13, 6, false, 15, 19},
    QpGolden{8, 0, 0, true, 0, 4}, QpGolden{8, 0, 16, true, 0, 0},
    QpGolden{8, 14, 0, true, 13, 14}, QpGolden{8, 14, 16, true, 3, 4},
    QpGolden{8, 3, 2, true, 1, 6}, QpGolden{8, 7, 8, true, 2, 4},
    QpGolden{8, 10, 14, true, 2, 3}, QpGolden{8, 13, 6, true, 7, 9},
    QpGolden{10, 0, 0, true, 0, 8}, QpGolden{10, 0, 22, true, 0, 0},
    QpGolden{10, 14, 0, true, 17, 18}, QpGolden{10, 14, 22, true, 4, 5},
    QpGolden{10, 3, 2, true, 5, 10}, QpGolden{10, 7, 11, true, 5, 7},
    QpGolden{10, 10, 20, true, 2, 3}, QpGolden{10, 13, 6, true, 11, 13},
    QpGolden{12, 0, 0, true, 0, 11}, QpGolden{12, 0, 28, true, 0, 0},
    QpGolden{12, 14, 0, true, 21, 22}, QpGolden{12, 14, 28, true, 4, 5},
    QpGolden{12, 3, 2, true, 9, 13}, QpGolden{12, 7, 14, true, 8, 9},
    QpGolden{12, 10, 26, true, 2, 3}, QpGolden{12, 13, 6, true, 15, 17}]!

struct QpFamily {
    bpc i32
    columns i32
    is_420 bool
}
const qp_families = [QpFamily{8, 37, false}, QpFamily{10, 49, false},
    QpFamily{12, 61, false}, QpFamily{8, 17, true},
    QpFamily{10, 23, true}, QpFamily{12, 29, true}]!

fn qp_tables() i32 {
    unsafe {
        for golden in qp_goldens {
            if C.intel_lookup_range_min_qp(golden.bpc, golden.row, golden.column, golden.is_420) != golden.minimum { return -5 }
            if C.intel_lookup_range_max_qp(golden.bpc, golden.row, golden.column, golden.is_420) != golden.maximum { return -5 }
        }
        // Every storage-valid half-step index, never outside the imported tables.
        for family in qp_families {
            for row := i32(0); row < 15; row++ {
                for column := i32(0); column < family.columns; column++ {
                    minimum := C.intel_lookup_range_min_qp(family.bpc, row, column, family.is_420)
                    maximum := C.intel_lookup_range_max_qp(family.bpc, row, column, family.is_420)
                    if minimum > maximum { return -5 }
                    if maximum > 23 { return -5 }
                }
            }
        }
        return 0
    }
}

struct DeviceGolden {
    major u32
    minor u32
    internal u32
    encoded u32
}
const device_goldens = [DeviceGolden{0, 0, 0x00000000, 0x00000000},
    DeviceGolden{0, 255, 0x000000ff, 0x000000ff},
    DeviceGolden{0, 256, 0x00000100, 0x00100000},
    DeviceGolden{255, 255, 0x0ff000ff, 0x0000ffff},
    DeviceGolden{256, 0, 0x10000000, 0x00010000},
    DeviceGolden{0xabc, 0x12345, 0xabc12345, 0x123abc45},
    DeviceGolden{0x123, 0xabcde, 0x123abcde, 0xabc123de},
    DeviceGolden{0xfff, 0xfffff, 0xffffffff, 0xffffffff}]!

fn device_numbers() i32 {
    unsafe {
        for golden in device_goldens {
            device := C.MKDEV(golden.major, golden.minor)
            if device != golden.internal { return -5 }
            if C.MAJOR(device) != golden.major || C.MINOR(device) != golden.minor { return -5 }
            if C.new_encode_dev(device) != golden.encoded { return -5 }
            if C.new_decode_dev(golden.encoded) != golden.internal { return -5 }
            if C.huge_encode_dev(device) != u64(golden.encoded) { return -5 }
            if C.huge_decode_dev(golden.encoded) != golden.internal { return -5 }
        }
        if !C.old_valid_dev(C.MKDEV(u32(255), u32(255))) { return -5 }
        if C.old_valid_dev(C.MKDEV(u32(256), u32(0))) { return -5 }
        if C.old_valid_dev(C.MKDEV(u32(0), u32(256))) { return -5 }
        if C.old_encode_dev(C.MKDEV(u32(255), u32(255))) != 0xffff { return -5 }
        if C.old_decode_dev(0xffff) != 0x0ff000ff { return -5 }
        if !C.sysv_valid_dev(C.MKDEV(u32(0xfff), u32(0x3ffff))) { return -5 }
        if C.sysv_valid_dev(C.MKDEV(u32(0), u32(0x40000))) { return -5 }
        if C.sysv_encode_dev(C.MKDEV(u32(0xabc), u32(0x12345))) != 0x2af12345 { return -5 }
        if C.sysv_major(0x2af12345) != 0xabc || C.sysv_minor(0x2af12345) != 0x12345 { return -5 }
        mut text := [32]char{}
        if C.format_dev_t(&text[0], C.MKDEV(u32(0xabc), u32(0x12345))) != &text[0] { return -5 }
        if C.strcmp(&text[0], c'2748:74565') != 0 { return -5 }
        if C.print_dev_t(&text[0], C.MKDEV(u32(0xabc), u32(0x12345))) != 11 { return -5 }
        if C.strcmp(&text[0], c'2748:74565\n') != 0 { return -5 }
        return 0
    }
}

@[export: 'vinix_linuxkpi_i915_policy_native_selftest']
pub fn run() i32 {
    flags := C.vinix_linuxkpi_irq_flags()
    depth := C.vinix_linuxkpi_preempt_count()
    unsafe {
        if C.i915_fence_context_timeout(nil, 0) != 0 { return -5 }
        if C.i915_fence_context_timeout(nil, 1) != 10001 { return -5 }
        if C.i915_fence_context_timeout(nil, u64(1) << 32) != 10001 { return -5 }
        if C.i915_fence_context_timeout(nil, u64(-1)) != 10001 { return -5 }
        if C.i915_fence_timeout(nil) != 10001 { return -5 }
    }
    if device_numbers() != 0 { return -5 }
    if qp_tables() != 0 { return -5 }
    if C.vinix_linuxkpi_irq_flags() != flags || C.vinix_linuxkpi_preempt_count() != depth { return -5 }
    return 0
}
