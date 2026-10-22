// SPDX-License-Identifier: GPL-2.0-or-later
// Graphics-symbol lookup for the Bionic linker. The native WS runtime loads
// its software EGL/GLES provider before APK libraries. Missing symbols remain
// linkage failures; lookup itself does not load another window system.
@[translated]
module wsloader

#include <dlfcn.h>

fn C.dlsym(voidptr, &char) voidptr

type GlLookup = fn (&char) voidptr

@[export: 'vinix_ws_gl_symbol']
pub fn graphics_symbol(name &char) voidptr {
	unsafe {
		if name == nil { return nil }
		resolved := C.dlsym(nil, name)
		if resolved != nil { return resolved }
		if name[0] != `g` || name[1] != `l` { return nil }
		lookup := GlLookup(C.dlsym(nil, c'_glapi_get_proc_address'))
		return if voidptr(lookup) == nil { nil } else { lookup(name) }
	}
}
