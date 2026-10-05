// SPDX-License-Identifier: GPL-2.0-or-later
module macho

pub struct Section {
pub:
	name    string
	address u64
	size    u64
	flags   u32
}

pub struct Segment {
pub:
	name     string
	address  u64
	size     u64
	fileoff  u64
	filesize u64
	prot     u32
	flags    u32
	sections []Section
}

pub struct Library {
pub:
	name string
	weak bool
}

pub struct Image {
pub:
	data             []u8
	subtype          u32
	filetype         u32
	flags            u32
	platform         u32
	minos            u32
	segments         []Segment
	libraries        []Library
	entryoff         u64
	stacksize        u64
	has_entry        bool
	fixup_offset     u64
	fixup_size       u64
	encrypted        bool
	legacy_fixups    bool
	initializers     bool
	thread_locals    bool
	required_unknown []u32
}

pub struct Layout {
pub:
	base  u64
	size  u64
	entry u64
}

// Prefer ordinary ARM64 over ARM64e regardless of universal-slice order.
// ARM64e remains inspectable so diagnostics can name its dependencies.
fn arm64_slice(data []u8) ![]u8 {
	r := Reader{data}
	magic := r.number(0, 4, true)!
	if magic == 0xcffaedfe {
		return data.clone()
	}
	if magic !in [u64(0xcafebabe), 0xcafebabf, 0xbebafeca, 0xbfbafeca] {
		return error('Mach-O: expected a 64-bit Mach-O or universal binary')
	}
	big := magic in [u64(0xcafebabe), 0xcafebabf]
	wide := magic in [u64(0xcafebabf), 0xbfbafeca]
	count := r.number(4, 4, big)!
	if count == 0 || count > 128 {
		return error('Mach-O: invalid universal slice count')
	}
	stride := u64(if wide { 32 } else { 20 })
	r.range(8, count * stride)!
	mut selected_offset := u64(0)
	mut selected_size := u64(0)
	mut preferred := false
	for i in u64(0) .. count {
		off := 8 + i * stride
		cpu := r.number(off, 4, big)!
		subtype := r.number(off + 4, 4, big)! & 0xffffff
		position := r.number(off + 8, if wide { 8 } else { 4 }, big)!
		size := r.number(off + if wide { 16 } else { 12 }, if wide { 8 } else { 4 }, big)!
		r.range(position, size)!
		if position < 8 + count * stride || size < 32 {
			return error('Mach-O: invalid universal slice range')
		}
		if cpu == 0x100000c && (!preferred || subtype == 0) {
			selected_offset = position
			selected_size = size
			preferred = subtype == 0
		}
	}
	if selected_size == 0 {
		return error('Mach-O: universal binary has no ARM64 slice')
	}
	return data[int(selected_offset)..int(selected_offset + selected_size)].clone()
}

pub fn parse(input []u8) !Image {
	data := arm64_slice(input)!
	r := Reader{data}
	r.range(0, 32)!
	if r.u32(0)! != 0xfeedfacf || r.u32(4)! != 0x100000c {
		return error('Mach-O: only little-endian 64-bit ARM64 images are supported')
	}
	count := r.u32(16)!
	command_bytes := u64(r.u32(20)!)
	r.range(32, command_bytes)!
	if u64(count) > command_bytes / 8 {
		return error('Mach-O: load command count exceeds command area')
	}
	mut segments := []Segment{}
	mut libraries := []Library{}
	mut required_unknown := []u32{}
	mut platform := u32(0)
	mut minos := u32(0)
	mut entryoff := u64(0)
	mut stacksize := u64(0)
	mut has_entry := false
	mut fixup_offset := u64(0)
	mut fixup_size := u64(0)
	mut encrypted := false
	mut legacy_fixups := false
	mut initializers := false
	mut thread_locals := false
	mut off := u64(32)
	for _ in 0 .. count {
		cmd := r.u32(off)!
		size := u64(r.u32(off + 4)!)
		if size < 8 || size % 8 != 0 || size > 32 + command_bytes - off {
			return error('Mach-O: invalid load command size')
		}
		match cmd {
			0x19 {
				if size < 72 {
					return error('Mach-O: truncated segment command')
				}
				address := r.u64(off + 24)!
				vmsize := r.u64(off + 32)!
				fileoff := r.u64(off + 40)!
				filesize := r.u64(off + 48)!
				r.range(fileoff, filesize)!
				end := checked_end(address, vmsize)!
				if filesize > vmsize {
					return error('Mach-O: segment file size exceeds memory size')
				}
				nsections := r.u32(off + 64)!
				if u64(nsections) > (size - 72) / 80 {
					return error('Mach-O: sections exceed segment command')
				}
				mut sections := []Section{}
				for index in 0 .. nsections {
					s := off + 72 + u64(index) * 80
					section_address := r.u64(s + 32)!
					section_size := r.u64(s + 40)!
					if section_address < address || checked_end(section_address, section_size)! > end {
						return error('Mach-O: section exceeds segment')
					}
					flags := r.u32(s + 64)!
					type_id := flags & 0xff
					initializers = initializers || type_id in [u32(9), 10, 0x16]
					thread_locals = thread_locals || (type_id >= 0x11 && type_id <= 0x15)
					sections << Section{r.name(s)!, section_address, section_size, flags}
				}
				prot := r.u32(off + 60)!
				if prot & ~u32(7) != 0 || prot & r.u32(off + 56)! != prot {
					return error('Mach-O: invalid segment protections')
				}
				segments << Segment{r.name(off + 8)!, address, vmsize, fileoff, filesize, prot, r.u32(off + 68)!, sections}
			}
			0xc, 0x80000018, 0x8000001f, 0x80000023 {
				if size < 24 {
					return error('Mach-O: truncated dylib command')
				}
				nameoff := u64(r.u32(off + 8)!)
				if nameoff < 24 || nameoff >= size {
					return error('Mach-O: invalid dylib name offset')
				}
				libraries << Library{r.string_at(off + nameoff, size - nameoff)!, cmd == 0x80000018}
				if cmd in [u32(0x8000001f), 0x80000023] {
					required_unknown << cmd
				}
			}
			0x80000028 {
				if size != 24 || has_entry {
					return error('Mach-O: invalid or duplicate LC_MAIN')
				}
				entryoff = r.u64(off + 8)!
				stacksize = r.u64(off + 16)!
				has_entry = true
			}
			0x80000034 {
				if size != 16 || fixup_size != 0 {
					return error('Mach-O: invalid or duplicate chained fixups command')
				}
				fixup_offset = u64(r.u32(off + 8)!)
				fixup_size = u64(r.u32(off + 12)!)
				r.range(fixup_offset, fixup_size)!
			}
			0x32 {
				if size < 24 || u64(r.u32(off + 20)!) > (size - 24) / 8 {
					return error('Mach-O: truncated build version command')
				}
				platform = r.u32(off + 8)!
				minos = r.u32(off + 12)!
			}
			0x24, 0x25, 0x2f, 0x30 {
				if size < 16 {
					return error('Mach-O: truncated minimum version command')
				}
				platform = match cmd {
					0x24 { u32(1) }
					0x25 { u32(2) }
					0x2f { u32(3) }
					else { u32(4) }
				}
				minos = r.u32(off + 8)!
			}
			0x21, 0x2c {
				if size < 20 {
					return error('Mach-O: truncated encryption command')
				}
				encrypted = encrypted || r.u32(off + 16)! != 0
			}
			0x22, 0x80000022 {
				if size < 48 {
					return error('Mach-O: truncated dyld info command')
				}
				for index in 0 .. 4 {
					legacy_fixups = legacy_fixups || r.u32(off + 12 + u64(index) * 8)! != 0
				}
			}
			0x1a {
				if size < 72 { return error('Mach-O: truncated routines command') }
				initializers = initializers || r.u64(off + 8)! != 0
			}
			// Metadata consumed neither by instruction execution nor binding.
			0x80000033, 0x8000001c {}
			else {
				if cmd & 0x80000000 != 0 {
					required_unknown << cmd
				}
			}
		}
		off += size
	}
	if off != 32 + command_bytes {
		return error('Mach-O: load commands do not fill command area')
	}
	return Image{
		data:             data
		subtype:          r.u32(8)!
		filetype:         r.u32(12)!
		flags:            r.u32(24)!
		platform:         platform
		minos:            minos
		segments:         segments
		libraries:        libraries
		entryoff:         entryoff
		stacksize:        stacksize
		has_entry:        has_entry
		fixup_offset:     fixup_offset
		fixup_size:       fixup_size
		encrypted:        encrypted
		legacy_fixups:    legacy_fixups
		initializers:     initializers
		thread_locals:    thread_locals
		required_unknown: required_unknown
	}
}

pub fn (image Image) platform_name() string {
	return match image.platform {
		1 { 'macOS' }
		2 { 'iOS' }
		6 { 'Mac Catalyst' }
		7 { 'iOS Simulator' }
		else { 'platform ${image.platform}' }
	}
}

pub fn (image Image) execution_issues() []string {
	mut issues := []string{}
	if image.subtype & 0xffffff != 0 {
		detail := if image.subtype & 0xffffff == 2 {
			' (ARM64e requires pointer authentication support)'
		} else {
			''
		}
		issues << 'CPU subtype ${image.subtype & 0xffffff} is not implemented${detail}'
	}
	if image.filetype != 2 { issues << 'only MH_EXECUTE is supported' }
	if image.flags & 0x200000 == 0 {
		issues << 'only position-independent executables (MH_PIE) can be relocated'
	}
	if image.platform !in [u32(2), 7] {
		issues << 'expected iOS or iOS Simulator, found ${image.platform_name()}'
	}
	if !image.has_entry { issues << 'LC_MAIN entry point is missing' }
	if image.stacksize != 0 { issues << 'custom LC_MAIN stack sizes are not implemented' }
	if image.encrypted {
		issues << 'encrypted executable; an unencrypted developer or simulator build is required'
	}
	if image.legacy_fixups { issues << 'legacy dyld rebase/bind opcodes are not implemented' }
	if image.initializers { issues << 'image initializers/terminators are not implemented' }
	if image.thread_locals { issues << 'Darwin thread-local storage is not implemented' }
	for command in image.required_unknown {
		issues << 'required load command 0x${command.hex()} is not implemented'
	}
	for library in image.libraries {
		if library.name !in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libobjc.A.dylib',
			'/System/Library/Frameworks/Foundation.framework/Foundation',
			'/System/Library/Frameworks/UIKit.framework/UIKit',
			'/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics'] && !library.weak {
			issues << 'framework/library is not implemented: ${library.name}'
		}
	}
	for segment in image.segments {
		if segment.flags & ~u32(0x14) != 0 {
			issues << 'segment flags 0x${segment.flags.hex()} are not implemented: ${segment.name}'
		}
	}
	return issues
}

pub fn (image Image) layout(page u64) !Layout {
	if page == 0 || page & (page - 1) != 0 {
		return error('Mach-O: invalid host page size')
	}
	mut base := ~u64(0)
	mut end := u64(0)
	mut entry := u64(0)
	mut found_entry := false
	mut ranges := []Segment{}
	for segment in image.segments {
		if segment.name == '__PAGEZERO' {
			if segment.filesize != 0 || segment.prot != 0 {
				return error('Mach-O: invalid __PAGEZERO segment')
			}
			continue
		}
		if segment.size == 0 { continue }
		if segment.address % page != 0 || segment.prot & 6 == 6 {
			return error('Mach-O: unaligned or writable executable segment')
		}
		segment_end := checked_end(segment.address, segment.size)!
		padded_end := checked_end(segment_end, page - 1)! & ~(page - 1)
		for previous in ranges {
			previous_end := (previous.address + previous.size + page - 1) & ~(page - 1)
			if segment.address < previous_end && previous.address < padded_end {
				return error('Mach-O: overlapping segments')
			}
		}
		ranges << segment
		if segment.address < base { base = segment.address }
		if padded_end > end { end = padded_end }
		if image.has_entry && segment.prot & 4 != 0 && image.entryoff >= segment.fileoff
			&& image.entryoff - segment.fileoff < segment.filesize {
			entry = segment.address + image.entryoff - segment.fileoff
			found_entry = true
		}
	}
	if end <= base || end - base > 512 * 1024 * 1024 || !found_entry || entry % 4 != 0 {
		return error('Mach-O: invalid image span or entry point')
	}
	return Layout{base, end - base, entry - base}
}
