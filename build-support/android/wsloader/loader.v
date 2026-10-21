// SPDX-License-Identifier: GPL-2.0-or-later
// Optional graphics-symbol lookup for the headless Bionic linker. The WS
// backend has no EGL context or GLES implementation. Missing symbols remain
// linkage failures; resolving a symbol never loads a display library.
@[translated]
module wsloader

#include <dlfcn.h>

fn C.dlsym(voidptr, &char) voidptr

@[export: 'vinix_ws_gl_symbol']
pub fn graphics_symbol(name &char) voidptr {
	return unsafe { C.dlsym(nil, name) }
}
