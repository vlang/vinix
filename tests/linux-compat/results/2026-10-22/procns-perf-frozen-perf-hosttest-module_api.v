// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

// Reuse the qualified default copy policy for newly owned source-tree destinations.
// Optional shutil.copytree policies are outside this interface.
pub fn module_copy_tree(source string, destination string) ! {
	module_copy(source, destination)!
}

// Text-mode subprocess output uses the same strict UTF-8 errors as source reads.
pub fn module_decode_utf8(text string) ! {
	module_utf8(text)!
}

// The source tools share the original host Python's Unicode 13 word boundaries.
pub fn module_word_rune(ch rune) bool {
	return module_word(ch)
}

// Host producers share the checked text-mode file policy, including original
// UTF-8 failures, newline conversion and literal Unix path bytes.
pub fn module_read_text(path string) !string { return module_read(path)! }
pub fn module_write_text(path string, text string) ! { module_write(path, text)! }

// Runtime staging needs shutil.copy2 semantics, including execute permission.
pub fn module_copy_file_preserving_stat(source string, destination string) ! {
	module_copy_file(source, destination)!
	module_copy_stat(source, destination)!
}

// Merged runtime trees preserve directory metadata after their children.
pub fn module_copy_directory_stat(source string, destination string) ! {
	module_copy_stat(source, destination)!
}

fn C.vinix_module_lstat_path(&char, &C.vinix_module_stat) i32
fn C.lchmod(&char, u32) i32
fn C.lchflags(&char, u32) i32

// Symlink staging preserves the link's own metadata without following a
// dangling or absolute target. C supplies only SDK filesystem primitives.
pub fn module_copy_link_stat(source string, destination string) ! {
	mut state := C.vinix_module_stat{}
	if C.vinix_module_lstat_path(source.str, &state) != 0 {
		return ModuleFileError{source, int(C.errno), 'Cannot inspect copied link'}
	}
	times := [C.timespec{state.st_atime, state.vinix_module_atime_nsec}, C.timespec{state.st_mtime, state.vinix_module_mtime_nsec}]!
	if C.utimensat(C.AT_FDCWD, destination.str, &times[0], C.AT_SYMLINK_NOFOLLOW) != 0 {
		return ModuleFileError{destination, int(C.errno), 'Cannot preserve link times'}
	}
	$if macos {
		if C.lchmod(destination.str, state.st_mode & 0o7777) != 0 && C.errno !in [C.ENOTSUP, C.EOPNOTSUPP] {
			return ModuleFileError{destination, int(C.errno), 'Cannot preserve link permissions'}
		}
		if C.lchflags(destination.str, state.st_flags) != 0 && C.errno !in [C.ENOTSUP, C.EOPNOTSUPP] {
			return ModuleFileError{destination, int(C.errno), 'Cannot preserve link flags'}
		}
	}
}
