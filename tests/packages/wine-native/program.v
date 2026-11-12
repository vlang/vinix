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
fn C.GetModuleHandleA(&char) voidptr
fn C.GetProcAddress(voidptr, &char) voidptr
fn C.VirtualFree(voidptr, C.ptrdiff_t, u32) bool
#define wine_memory_information MEMORY_BASIC_INFORMATION
#define wine_virtual_query VirtualQuery
@[typedef]
struct C.wine_memory_information {
	Protect u32
	AllocationProtect u32
	Type u32
}
fn C.wine_virtual_query(voidptr, &C.wine_memory_information, u64) u64

type ExecutableProbe = fn () int

fn image_memory() bool {
	image := C.GetModuleHandleA(unsafe { nil })
	mut info := C.wine_memory_information{}
	if C.wine_virtual_query(image, &info, sizeof(C.wine_memory_information)) == 0
		|| info.Protect != 2 || info.AllocationProtect != 0x80 { return false }
	code := C.GetProcAddress(C.GetModuleHandleA(c'kernel32.dll'), c'GetCurrentProcessId')
	if code == unsafe { nil } || C.wine_virtual_query(code, &info, sizeof(C.wine_memory_information)) == 0
		|| info.Protect != 0x20 || info.Type != 0x1000000 { return false }
	// Changing image protection must retain the original view's execute access.
	mut old := C.DWORD(0)
	if !C.VirtualProtect(code, 1, 0x20, &old) || old != 0x20 { return false }
	return true
}

fn wx_memory() bool {
	page := C.VirtualAlloc(unsafe { nil }, 4096, 0x3000, 4)
	if page == unsafe { nil } { return false }
	defer { C.VirtualFree(page, 0, 0x8000) }
	// AMD64: mov eax,42; ret. Write while RW, execute only after RX succeeds.
	bytes := [u8(0xb8), 42, 0, 0, 0, 0xc3]!
	unsafe { vmemcpy(page, &bytes[0], bytes.len) }
	mut old := C.DWORD(0)
	if !C.VirtualProtect(page, 4096, 0x20, &old) || old != 4 { return false }
	probe := unsafe { ExecutableProbe(page) }
	if probe() != 42 { return false }
	// Neither initial allocation nor a protection transition may create W+X.
	if C.VirtualProtect(page, 4096, 0x40, &old) { return false }
	bad := C.VirtualAlloc(unsafe { nil }, 4096, 0x3000, 0x40)
	if bad != unsafe { nil } { C.VirtualFree(bad, 0, 0x8000); return false }
	return true
}

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
	if !image_memory() { exit(27) }
	output := C.GetStdHandle(u32(0xfffffff5))
	if !write(output, 'VINIX SIGNED WIN64 IMAGE PROTECTION PASS\n') { exit(29) }
	// QEMU translates guest permissions through split RW/RX aliases; native
	// x86 must exercise the kernel's direct W^X refusal as well.
	if variable(c'VINIX_APP_ARCHITECTURE', 'x86_64') {
		if !wx_memory() { exit(28) }
		if !write(output, 'VINIX SIGNED WIN64 WX PASS\n') { exit(29) }
	} else if !variable(c'VINIX_APP_ARCHITECTURE', 'aarch64') { exit(29) }
	file := C.CreateFileA(c'C:\\users\\vinix\\Temp\\real-win64.txt', 0x40000000, 0, unsafe { nil }, 2, 0x80, unsafe { nil })
	if file == voidptr(int(-1)) { exit(22) }
	if !write(file, 'real Win64 Windows API execution\r\n') { C.CloseHandle(file); exit(23) }
	C.CloseHandle(file)
	denied := C.CreateFileA(c'Z:\\home\\alex\\denied-wine.txt', 0x40000000, 0, unsafe { nil }, 2, 0x80, unsafe { nil })
	if denied != voidptr(int(-1)) { C.CloseHandle(denied); exit(26) }
	if !write(C.GetStdHandle(u32(0xfffffff5)), 'VINIX SIGNED REAL WIN64 READY\n') { exit(24) }
	// Let the native observer inspect actual Wine/translator UID and socket DAC.
	C.Sleep(5000)
	if !write(C.GetStdHandle(u32(0xfffffff5)), 'VINIX SIGNED REAL WIN64 PASS\n') { exit(25) }
}
