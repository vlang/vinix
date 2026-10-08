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
