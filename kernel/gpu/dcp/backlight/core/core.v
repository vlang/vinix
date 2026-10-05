// SPDX-License-Identifier: GPL-2.0-only OR MIT
// Copyright (c) 2026 Alexander Medvednikov
// Copyright (C) The Asahi Linux Contributors
//
// Calibration and wire layouts follow AsahiLinux/linux dcp_backlight.c
// (9eb0c7d4eb5345178f802e55dc8e8a3dbdbea8cd), iomfb_template.h
// (8efab49cc53d08964a5da5476fb99c050923aaa2) and iomfb_template.c
// (cf40e273a2f43cd6576857f45e89a9edb4e5c841). See tools/apple-backlight.
//
// Allocation-free, platform-independent V. This is the backlight state and
// wire codec, NOT a DCP transport. The caller serializes each State and owns
// firmware RPCs, DMA visibility, timeouts and the lifetime of scanout surfaces.
module core

pub const min_nits = u32(2)
pub const max_nits = u32(509)
pub const text_capacity = 192
pub const write_limit = 16
pub const property_nits = u32(15)

// These are explicit wire-layout families, not firmware >= comparisons.
pub enum Layout {
	unsupported
	v12_3
	v13_3
}

// Plain values avoid allocating error objects in the freestanding kernel.
pub enum Status {
	ok          = 0
	idle        = 1
	invalid     = -1
	unsupported = -2
	offline     = -3
	busy        = -4
	stale       = -5
	overflow    = -6
}

pub struct State {
mut:
	layout            Layout
	maximum           u32
	scale             u32
	requested         u32
	actual            u32
	generation        u64
	active_generation u64
	next_token        u64
	active_token      u64
	online            bool
	have_request      bool
	actual_valid      bool
	pending           bool
	inflight          bool
}

const interpolation_scale = u32(1024)
const brightness_part1 = [
	u32(0x0000000),
	0x0810038,
	0x0f000bd,
	0x143011c,
	0x1850165,
	0x1bc01a1,
	0x1eb01d4,
	0x2140200,
	0x2380227,
	0x2590249,
	0x2770269,
	0x2930285,
	0x2ac02a0,
	0x2c402b8,
	0x2d902cf,
	0x2ee02e4,
	0x30102f8,
	0x314030b,
	0x325031c,
	0x335032d,
	0x345033d,
	0x354034d,
	0x362035b,
	0x3700369,
	0x37d0377,
	0x38a0384,
	0x3960390,
	0x3a2039c,
	0x3ad03a7,
	0x3b803b3,
	0x3c303bd,
	0x3cd03c8,
	0x3d703d2,
	0x3e103dc,
	0x3ea03e5,
	0x3f303ef,
	0x3fc03f8,
	0x4050400,
	0x40d0409,
	0x4150411,
	0x41d0419,
	0x4250421,
	0x42d0429,
	0x4340431,
	0x43c0438,
	0x443043f,
	0x44a0446,
	0x451044d,
	0x4570454,
	0x45e045b,
	0x4640461,
	0x46b0468,
	0x471046e,
	0x4770474,
	0x47d047a,
	0x4830480,
	0x4890486,
	0x48e048b,
	0x4940491,
	0x4990497,
	0x49f049c,
	0x4a404a1,
	0x4a904a7,
	0x4ae04ac,
	0x4b304b1,
	0x4b804b6,
	0x4bd04bb,
	0x4c204c0,
	0x4c704c5,
	0x4cc04c9,
	0x4d004ce,
	0x4d504d3,
	0x4d904d7,
	0x4de04dc,
	0x4e204e0,
	0x4e704e4,
	0x4eb04e9,
	0x4ef04ed,
	0x4f304f1,
	0x4f704f5,
	0x4fb04f9,
	0x4ff04fd,
	0x5030501,
	0x5070505,
	0x50b0509,
	0x50f050d,
	0x5130511,
	0x5160515,
	0x51a0518,
	0x51e051c,
	0x5210520,
	0x5250523,
	0x5290527,
	0x52c052a,
	0x52f052e,
	0x5330531,
	0x5360535,
	0x53a0538,
	0x53d053b,
	0x540053f,
	0x5440542,
	0x5470545,
	0x54a0548,
	0x54d054c,
	0x550054f,
	0x5530552,
	0x5560555,
	0x5590558,
	0x55c055b,
	0x55f055e,
	0x5620561,
	0x5650564,
	0x5680567,
	0x56b056a,
	0x56e056d,
	0x571056f,
	0x5740572,
	0x5760575,
	0x5790578,
	0x57c057b,
	0x57f057d,
	0x5810580,
	0x5840583,
	0x5870585,
	0x5890588,
	0x58c058b,
	0x58f058d,
]!

const brightness_part12 = [
	u32(0x58f058d),
	0x59d058f,
]!

const brightness_part2 = [
	u32(0x59d058f),
	0x5b805ab,
	0x5d105c5,
	0x5e805dd,
	0x5fe05f3,
	0x6120608,
	0x625061c,
	0x637062e,
	0x6480640,
	0x6580650,
	0x6680660,
	0x677066f,
	0x685067e,
	0x693068c,
	0x6a00699,
	0x6ac06a6,
	0x6b806b2,
	0x6c406be,
	0x6cf06ca,
	0x6da06d5,
	0x6e506df,
	0x6ef06ea,
	0x6f906f4,
	0x70206fe,
	0x70c0707,
	0x7150710,
	0x71e0719,
	0x7260722,
	0x72f072a,
	0x7370733,
	0x73f073b,
	0x7470743,
	0x74e074a,
	0x7560752,
	0x75d0759,
	0x7640760,
	0x76b0768,
	0x772076e,
	0x7780775,
	0x77f077c,
	0x7850782,
	0x78c0789,
	0x792078f,
	0x7980795,
	0x79e079b,
	0x7a407a1,
	0x7aa07a7,
	0x7af07ac,
	0x7b507b2,
	0x7ba07b8,
	0x7c007bd,
	0x7c507c2,
	0x7ca07c8,
	0x7cf07cd,
	0x7d407d2,
	0x7d907d7,
	0x7de07dc,
	0x7e307e1,
	0x7e807e5,
	0x7ec07ea,
	0x7f107ef,
	0x7f607f3,
	0x7fa07f8,
	0x7fe07fc,
]!

// Interpolate the packed calibration word before multiplying by sixteen.
// Interpolating its halves separately changes the established calibration.
fn interpolate(value u32, low u32, high u32, table &u32, length int) u32 {
	position := u32(length - 1) * ((value - low) * interpolation_scale) / (high - low)
	index := int(position / interpolation_scale)
	fraction := position % interpolation_scale
	return u32((u64(fraction) * unsafe { table[index + 1] } + u64(interpolation_scale - fraction) * unsafe { table[index] }) / interpolation_scale)
}

pub fn nits_to_dac(nits u32) ?u32 {
	if nits < min_nits || nits > max_nits {
		return none
	}
	value := if nits == 2 {
		brightness_part1[0]
	} else if nits == 99 {
		brightness_part1[brightness_part1.len - 1]
	} else if nits == 103 {
		brightness_part2[0]
	} else if nits < 99 {
		interpolate(nits, 2, 99, &brightness_part1[0], brightness_part1.len)
	} else if nits < 103 {
		interpolate(nits, 99, 103, &brightness_part12[0], brightness_part12.len)
	} else {
		interpolate(nits, 103, 510, &brightness_part2[0], brightness_part2.len)
	}
	return value * 16
}

// One whole unsigned decimal nit command; at most one trailing LF.
pub fn parse_nits(text []u8) ?u32 {
	if text.len == 0 || text.len > write_limit {
		return none
	}
	length := if text[text.len - 1] == `\n` { text.len - 1 } else { text.len }
	if length == 0 {
		return none
	}
	mut value := u32(0)
	for byte in text[..length] {
		if byte < `0` || byte > `9` {
			return none
		}
		digit := u32(byte - `0`)
		if value > (max_nits - digit) / 10 {
			return none
		}
		value = value * 10 + digit
	}
	if value < min_nits {
		return none
	}
	return value
}

// No casts to packed structs or unaligned integer pointers. Only the 13
// backlight bytes change; all flags, surfaces and timestamps are preserved.
pub fn patch_swap(layout Layout, nits u32, mut swap []u8) Status {
	offset, size := match layout {
		.v12_3 { 0x2e6, 0x320 }
		.v13_3 { 0x2e7, 0x468 }
		else {
			return .unsupported
		}
	}
	if swap.len < size {
		return .invalid
	}
	dac := nits_to_dac(nits) or { return .invalid }
	swap[offset] = 1
	for i in 1 .. 8 {
		swap[offset + i] = 0
	}
	for i in 0 .. 4 {
		swap[offset + 8 + i] = u8(dac >> (8 * i))
	}
	swap[offset + 12] = 0x40
	return .ok
}

// Call once per lifetime, NOT on firmware restart: old tokens must stay stale.
// Failed initialization leaves the existing state unchanged.
pub fn (mut s State) initialise(layout Layout, panel_max_nits u32, scale u32,
	initial_raw_nits u32, initial_valid bool) Status {
	if panel_max_nits < min_nits || scale == 0 {
		return .invalid
	}
	if layout != .v12_3 && layout != .v13_3 {
		return .unsupported
	}
	actual := if initial_valid { initial_raw_nits / scale } else { u32(0) }
	if actual > panel_max_nits {
		return .invalid
	}
	s = State{
		layout: layout
		maximum: if panel_max_nits < max_nits { panel_max_nits } else { max_nits }
		scale: scale
		actual: actual
		actual_valid: initial_valid
	}
	return .ok
}

pub fn (mut s State) set_online(online bool) Status {
	if s.scale == 0 {
		return .invalid
	}
	if s.online == online {
		return .ok
	}
	s.online = online
	s.inflight = false
	s.active_token = 0
	s.pending = s.have_request
	if !online {
		s.actual_valid = false
	}
	return .ok
}

pub fn (mut s State) request(nits u32) Status {
	if s.scale == 0 || nits < min_nits || nits > s.maximum {
		return .invalid
	}
	if !s.online {
		return .offline
	}
	if s.generation == ~u64(0) {
		return .overflow
	}
	s.generation++
	s.requested = nits
	s.have_request = true
	s.pending = true
	return .ok
}

pub fn (mut s State) write(text []u8) Status {
	nits := parse_nits(text) or { return .invalid }
	return s.request(nits)
}

// A token is returned only when a pending update was patched successfully.
// Idle and all failures leave both the swap buffer and state unchanged.
pub fn (mut s State) prepare(mut swap []u8) (Status, u64) {
	if s.scale == 0 {
		return Status.invalid, 0
	}
	if !s.online {
		return Status.offline, 0
	}
	if s.inflight {
		return Status.busy, 0
	}
	if !s.pending {
		return Status.idle, 0
	}
	if s.next_token == ~u64(0) {
		return Status.overflow, 0
	}
	result := patch_swap(s.layout, s.requested, mut swap)
	if result != .ok {
		return result, 0
	}
	s.active_generation = s.generation
	s.next_token++
	s.active_token = s.next_token
	s.inflight = true
	return Status.ok, s.active_token
}

// accepted means a matched successful firmware response, not mailbox send.
// A timeout must fault/quiesce the real transport before a retry is safe.
pub fn (mut s State) complete(token u64, accepted bool) Status {
	if s.scale == 0 {
		return .invalid
	}
	if !s.online {
		return .offline
	}
	if token == 0 || !s.inflight || token != s.active_token {
		return .stale
	}
	s.pending = !accepted || s.generation != s.active_generation
	s.inflight = false
	s.active_token = 0
	return .ok
}

// Measurement comes only from IOMFB property 15, divided by Brightness_Scale.
// It may be outside the writable calibrated range, including a blanked panel.
pub fn (mut s State) publish(raw_nits u32) Status {
	if s.scale == 0 {
		return .invalid
	}
	if !s.online {
		return .offline
	}
	s.actual = raw_nits / s.scale
	s.actual_valid = true
	return .ok
}

struct TextWriter {
mut:
	data [text_capacity]u8
	used int
}

fn (mut w TextWriter) text(text string) {
	for byte in text {
		w.data[w.used] = byte
		w.used++
	}
}

fn (mut w TextWriter) number(input u32) {
	mut digits := [10]u8{}
	mut length := 0
	mut value := input
	for {
		digits[length] = u8(`0` + value % 10)
		length++
		value /= 10
		if value == 0 {
			break
		}
	}
	for length > 0 {
		length--
		w.data[w.used] = digits[length]
		w.used++
	}
}

// Format atomically into caller-owned storage. No allocation, sprintf or C
// buffers. The extra NUL matches the old internal API; it is not read out.
pub fn (s &State) format(mut text []u8) ?int {
	if s.scale == 0 {
		return none
	}
	mut w := TextWriter{}
	w.text('requested_nits=')
	if s.have_request { w.number(s.requested) } else { w.text('unknown') }
	w.text('\nactual_nits=')
	if s.actual_valid { w.number(s.actual) } else { w.text('unknown') }
	w.text('\nmin_nits=2\nmax_nits=')
	w.number(s.maximum)
	w.text('\npending=')
	w.number(u32(if s.pending { 1 } else { 0 }))
	w.text('\nonline=')
	w.number(u32(if s.online { 1 } else { 0 }))
	w.text('\n')
	if text.len <= w.used {
		return none
	}
	for i in 0 .. w.used {
		text[i] = w.data[i]
	}
	text[w.used] = 0
	return w.used
}
