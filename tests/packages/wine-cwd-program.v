// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone unsigned Win64 diagnostic, not a packaged application.
module main

#include <windows.h>
fn C.GetCurrentDirectoryA(u32, &char) u32
fn C.GetEnvironmentVariableA(&char, &char, u32) u32
fn C.GetStdHandle(u32) voidptr
fn C.CreateFileA(&char, u32, u32, voidptr, u32, u32, voidptr) voidptr
fn C.ReadFile(voidptr, voidptr, u32, &C.DWORD, voidptr) int
fn C.WriteFile(voidptr, voidptr, u32, &C.DWORD, voidptr) int
fn C.CloseHandle(voidptr) int
fn C.GetCommandLineA() &char
@[typedef]
struct C.STARTUPINFOA { mut: cb u32 }
@[typedef]
struct C.PROCESS_INFORMATION { hProcess voidptr hThread voidptr }
fn C.CreateProcessA(&char, &char, voidptr, voidptr, int, u32, voidptr, &char, &C.STARTUPINFOA, &C.PROCESS_INFORMATION) int
fn C.WaitForSingleObject(voidptr, u32) u32
fn C.GetExitCodeProcess(voidptr, &C.DWORD) int
fn C.TerminateProcess(voidptr, u32) int

fn cwd_matches() bool {
	mut actual := [1024]u8{}
	mut expected := [1024]u8{}
	a := C.GetCurrentDirectoryA(1024, &char(&actual[0]))
	b := C.GetEnvironmentVariableA(c'VINIX_CWD_EXPECTED', &char(&expected[0]), 1024)
	if a == 0 || a >= 1024 || a != b { return false }
	for index in 0 .. int(a) { if actual[index] != expected[index] { return false } }
	return true
}

fn read_relative() bool {
	file := C.CreateFileA(c'input space.txt', 0x80000000, 1, unsafe { nil }, 3, 0x80, unsafe { nil })
	if file == voidptr(int(-1)) { return false }
	defer { C.CloseHandle(file) }
	mut bytes := [64]u8{}
	mut count := C.DWORD(0)
	if C.ReadFile(file, &bytes[0], 64, &count, unsafe { nil }) == 0 || count != 21 { return false }
	for index, byte in 'captured Windows cwd\n' { if bytes[index] != byte { return false } }
	return true
}

fn write_text(file voidptr, text string) bool {
	mut count := C.DWORD(0)
	return C.WriteFile(file, text.str, u32(text.len), &count, unsafe { nil }) != 0 && count == u32(text.len)
}

fn child() bool {
	mut start := C.STARTUPINFOA{cb: sizeof(C.STARTUPINFOA)}
	mut process := C.PROCESS_INFORMATION{}
	// The application name is relative and contains spaces. The mutable command
	// line quotes argv[0]; lpCurrentDirectory=NULL must inherit the parent cwd.
	mut command := '"cwd program.exe" --cwd-child'.bytes()
	command << u8(0)
	if C.CreateProcessA(c'cwd program.exe', &char(command.data), unsafe { nil }, unsafe { nil }, 0, 0,
		unsafe { nil }, unsafe { nil }, &start, &process) == 0 { return false }
	defer { C.CloseHandle(process.hThread); C.CloseHandle(process.hProcess) }
	if C.WaitForSingleObject(process.hProcess, 15000) != 0 { C.TerminateProcess(process.hProcess, 99); C.WaitForSingleObject(process.hProcess, 5000); return false }
	mut status := C.DWORD(0)
	return C.GetExitCodeProcess(process.hProcess, &status) != 0 && status == 0
}

fn main() {
	if !cwd_matches() { exit(41) }
	if !read_relative() { exit(42) }
	command := C.GetCommandLineA()
	is_child := command != unsafe { nil } && unsafe { cstring_to_vstring(command) }.ends_with(' --cwd-child')
	name := if is_child { c'child output.txt' } else { c'parent output.txt' }
	file := C.CreateFileA(name, 0x40000000, 0, unsafe { nil }, 1, 0x80, unsafe { nil })
	if file == voidptr(int(-1)) { exit(43) }
	if !write_text(file, if is_child { 'child relative write\n' } else { 'parent relative write\n' }) { C.CloseHandle(file); exit(44) }
	if C.CloseHandle(file) == 0 { exit(45) }
	if is_child { exit(0) }
	if !child() { exit(46) }
	if !write_text(C.GetStdHandle(u32(0xfffffff5)), 'WINE WINDOWS CWD PASS current directory; relative read/write; child inheritance\n') { exit(47) }
}
