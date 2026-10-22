// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module wsloader

#include <stdio.h>

fn C.dprintf(i32, &char, ...voidptr) i32

@[export: 'vinix_ws_link_failure']
pub fn link_failure(name &char, detail &char) {
	C.dprintf(2, c'VINIX-ANDROID-LINK-FAIL library=%s error=%s\n', name, detail)
}

// Host dlopen succeeds without a Bionic soinfo. Neither kind of handle means
// the dependency failed: preserve its linker error and reject the parent.
@[export: 'vinix_ws_dependency_loaded']
pub fn dependency_loaded(own voidptr, host voidptr, name &char, parent &char, detail &char) i32 {
	if own != unsafe { nil } || host != unsafe { nil } { return 1 }
	C.dprintf(2, c'VINIX-ANDROID-DEPENDENCY-FAIL library=%s needed=%s error=%s\n', parent, name, detail)
	return 0
}

type LibraryLookup = fn (voidptr, &char) voidptr

struct DynamicEntry {
	tag i64
	value usize
}

// dlsym(handle) searches the handle and its DT_NEEDED closure breadth first.
// The pinned linker replaces each dependency name with its retained soinfo.
// Its pool holds at most 128 objects, plus the built-in libdl object.
@[export: 'vinix_ws_lookup_dependencies']
pub fn lookup_dependencies(root voidptr, name &char, found &voidptr, dynamic_offset usize, lookup LibraryLookup) voidptr {
	unsafe {
		*found = nil
		if root == nil || name == nil { return nil }
		mut queue := [256]voidptr{}
		queue[0] = root
		mut count := 1
		for current := 0; current < count; current++ {
			node := queue[current]
			symbol := lookup(node, name)
			if symbol != nil {
				info := (&u8(symbol))[4]
				section := (&u16(symbol))[3]
				if section != 0 && (info >> 4 == 1 || info >> 4 == 2) {
					*found = node
					return symbol
				}
			}
			dynamic := *(&&DynamicEntry(&u8(node) + dynamic_offset))
			if dynamic == nil { continue }
			for index := 0; dynamic[index].tag != 0; index++ {
				if dynamic[index].tag != 1 || dynamic[index].value == 0 { continue }
				child := voidptr(dynamic[index].value)
				mut visited := false
				for previous in 0 .. count {
					if queue[previous] == child { visited = true; break }
				}
				if !visited {
					if count == queue.len { return nil }
					queue[count] = child
					count++
				}
			}
		}
		return nil
	}
}
