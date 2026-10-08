// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
module fonthost

import fixturehost
import os

fn make_directory(path string, parents bool) ! {
	if path.contains('\x00') { return FontError{'ValueError', 'embedded null byte'} }
    os.mkdir(path) or {
        if parents && err.code() == 2 {
            parent := path.trim_right('/').all_before_last('/')
            if parent != '' && parent != path {
                make_directory(parent, true)!
                make_directory(path, false)!
                return
            }
        }
        if !os.is_dir(path) { return fixturehost.FileError{path, err.code(), os.get_error_msg(err.code())} }
	}
}
