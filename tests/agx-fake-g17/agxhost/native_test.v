// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import hosttest
import fixturehost
import os
import encoding.hex

fn test_inherited_environment_owns_raw_byte_keys_and_values() {
	mut encoded := '4b45593d6f776e656400454d5054593d00455155414c533d613d62006c69746572616c5c6b65793dff00'.clone()
	environment := native_environment(encoded) or { panic(err) }
	unsafe { encoded.free() }
	encoded = ''
	assert environment['KEY'] == 'owned'
	assert environment['EMPTY'] == ''
	assert environment['EQUALS'] == 'a=b'
	assert hex.encode(environment['literal\\key'].bytes()) == 'ff'
}

fn test_original_pathlib_argument_components() {
	assert native_argument_path("") == "."
	assert native_argument_path(".") == "."
	assert native_argument_path("./") == "."
	assert native_argument_path("x/./y/") == "x/y"
	assert native_argument_path("x//y") == "x/y"
	assert native_argument_path("///") == "/"
	assert native_argument_path("//") == "//"
	assert native_argument_path("/") == "/"
	assert native_argument_path("//host//x/./y/") == "//host/x/y"
	assert native_argument_path("../../../x") == "../../../x"
	assert native_argument_path("a\\literal/雪/../") == "a\\literal/雪/.."
	assert native_argument_path(".hidden") == ".hidden"
	assert native_argument_path("a/..") == "a/.."
	assert native_argument_path("/./../") == "/.."
	assert native_argument_path("b") == "b"
	assert native_argument_path("./b") == "b"
	assert native_argument_path("../b") == "../b"
	assert native_argument_path("b//c") == "b/c"
	assert native_argument_path("..") == ".."
	assert native_argument_path("é/😀") == "é/😀"
	assert native_argument_path("path\\literal") == "path\\literal"
	assert native_argument_path("/b") == "/b"
	assert native_argument_path("/./b") == "/b"
	assert native_argument_path("/../b") == "/../b"
	assert native_argument_path("/b//c") == "/b/c"
	assert native_argument_path("/.") == "/"
	assert native_argument_path("/..") == "/.."
	assert native_argument_path("/é/😀") == "/é/😀"
	assert native_argument_path("/path\\literal") == "/path\\literal"
	assert native_argument_path("//b") == "//b"
	assert native_argument_path("//./b") == "//b"
	assert native_argument_path("//../b") == "//../b"
	assert native_argument_path("//b//c") == "//b/c"
	assert native_argument_path("//.") == "//"
	assert native_argument_path("//..") == "//.."
	assert native_argument_path("//é/😀") == "//é/😀"
	assert native_argument_path("//path\\literal") == "//path\\literal"
	assert native_argument_path("///b") == "/b"
	assert native_argument_path("///./b") == "/b"
	assert native_argument_path("///../b") == "/../b"
	assert native_argument_path("///b//c") == "/b/c"
	assert native_argument_path("///.") == "/"
	assert native_argument_path("///..") == "/.."
	assert native_argument_path("///é/😀") == "/é/😀"
	assert native_argument_path("///path\\literal") == "/path\\literal"
	assert native_argument_path("././b") == "b"
	assert native_argument_path("./../b") == "../b"
	assert native_argument_path("./b//c") == "b/c"
	assert native_argument_path("./.") == "."
	assert native_argument_path("./..") == ".."
	assert native_argument_path("./é/😀") == "é/😀"
	assert native_argument_path("./path\\literal") == "path\\literal"
	assert native_argument_path("../") == ".."
	assert native_argument_path(".././b") == "../b"
	assert native_argument_path("../../b") == "../../b"
	assert native_argument_path("../b//c") == "../b/c"
	assert native_argument_path("../.") == ".."
	assert native_argument_path("../..") == "../.."
	assert native_argument_path("../é/😀") == "../é/😀"
	assert native_argument_path("../path\\literal") == "../path\\literal"
	assert native_argument_path("a/") == "a"
	assert native_argument_path("a/b") == "a/b"
	assert native_argument_path("a/./b") == "a/b"
	assert native_argument_path("a/../b") == "a/../b"
	assert native_argument_path("a/b//c") == "a/b/c"
	assert native_argument_path("a/.") == "a"
	assert native_argument_path("a/é/😀") == "a/é/😀"
	assert native_argument_path("a/path\\literal") == "a/path\\literal"
}

fn test_owned_native_source_walk_and_exclusive_directories() {
	work := hosttest.work_dir("", "vinix-native-path-") or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	child := work + "/literal\\name/雪"
	native_mkdir(child, true, false) or { panic(err) }
	assert !os.exists(work + "/literal")
	fixturehost.write(child + "/fixture.v", "module fixture") or { panic(err) }
	fixturehost.write(work + "/header.h", "header") or { panic(err) }
	paths := native_input_paths(work) or { panic(err) }
	assert paths == [work + "/header.h", child + "/fixture.v"]
	native_mkdir(child, true, false) or {
		assert err is hosttest.ModuleFileError && err.filename == child && err.number == 17
		return
	}
	assert false
}
