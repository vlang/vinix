// SPDX-License-Identifier: GPL-2.0-or-later
// A real Win64 executable. Only Wine can execute these Windows API calls.
module main

#include <windows.h>
fn C.GetStdHandle(u32) voidptr
fn C.WriteFile(voidptr, voidptr, u32, voidptr, voidptr) int
fn C.GetEnvironmentVariableA(&char, &char, u32) u32
fn C.CreateFileA(&char, u32, u32, voidptr, u32, u32, voidptr) voidptr
fn C.CloseHandle(voidptr) int
fn C.Sleep(u32)

fn variable(name &char, expected string) bool {
	mut buffer := [4096]u8{}
	length := C.GetEnvironmentVariableA(name, &char(&buffer[0]), u32(buffer.len))
	return length == u32(expected.len) && unsafe { tos(&buffer[0], int(length)) } == expected
}

fn write(handle voidptr, text string) bool {
	mut count := u32(0)
	return C.WriteFile(handle, text.str, u32(text.len), voidptr(&count), unsafe { nil }) != 0 && count == u32(text.len)
}

fn main() {
	if !variable(c'VINIX_APP_ID', 'org.vinix.wine-win64-probe') || !variable(c'VINIX_APP_KIND', 'windows') ||
		!variable(c'VINIX_APP_RUNTIME_ID', 'org.vinix.wine-runtime') || !variable(c'USER', 'vinix') ||
		!variable(c'WINEARCH', 'win64') { exit(21) }
	file := C.CreateFileA(c'C:\\users\\vinix\\Temp\\real-win64.txt', 0x40000000, 0, unsafe { nil }, 2, 0x80, unsafe { nil })
	if file == voidptr(isize(-1)) { exit(22) }
	if !write(file, 'real Win64 Windows API execution\r\n') { C.CloseHandle(file); exit(23) }
	C.CloseHandle(file)
	denied := C.CreateFileA(c'Z:\\home\\alex\\denied-wine.txt', 0x40000000, 0, unsafe { nil }, 2, 0x80, unsafe { nil })
	if denied != voidptr(isize(-1)) { C.CloseHandle(denied); exit(26) }
	if !write(C.GetStdHandle(u32(0xfffffff5)), 'VINIX SIGNED REAL WIN64 READY\n') { exit(24) }
	// Let the native observer inspect actual Wine/translator UID and socket DAC.
	C.Sleep(5000)
	if !write(C.GetStdHandle(u32(0xfffffff5)), 'VINIX SIGNED REAL WIN64 PASS\n') { exit(25) }
}
