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

// Keep the callback's exact C LONG type: V's Windows alias lowers to int,
// which has the same width but is incompatible with MinGW's long callback.
#define wine_exception_result LONG
@[typedef]
struct C.wine_exception_result {}
@[typedef]
struct C.EXCEPTION_RECORD {
	ExceptionCode u32
	ExceptionFlags u32
	ExceptionAddress voidptr
	NumberParameters u32
	ExceptionInformation [15]u64
}
@[typedef]
struct C.CONTEXT {
mut:
	Rax u64
	Rcx u64
	Rip u64
}
@[typedef]
struct C.EXCEPTION_POINTERS {
	ExceptionRecord &C.EXCEPTION_RECORD
	ContextRecord &C.CONTEXT
}
fn C.AddVectoredExceptionHandler(u32, fn (&C.EXCEPTION_POINTERS) C.wine_exception_result) voidptr
fn C.RemoveVectoredExceptionHandler(voidptr) u32
fn C.RaiseException(u32, u32, u32, &u64)

struct ExceptionOrder {
mut:
	visits int
}

type ReadProbe = fn (voidptr) int

// Recognize only this fixture's continuable software exception. Its borrowed
// stack record is alive until RaiseException returns; callbacks allocate nothing.
fn software_exception(info &C.EXCEPTION_POINTERS, digit int) bool {
	record := info.ExceptionRecord
	if record.ExceptionCode != 0xe042564e || record.ExceptionFlags != 0
		|| record.NumberParameters != 3 || record.ExceptionInformation[1] != 0x56494e4958
		|| record.ExceptionInformation[2] !in [u64(1), 2] { return false }
	mut order := unsafe { &ExceptionOrder(record.ExceptionInformation[0]) }
	order.visits = order.visits * 10 + digit
	return digit == 2 || record.ExceptionInformation[2] == 1
}

// The only hardware fault accepted is the fixture's two-byte read instruction,
// followed by RET and an identifying byte sequence, against a PAGE_NOACCESS page.
// Returning through the modified context proves both RIP and RAX restoration.
fn read_exception(info &C.EXCEPTION_POINTERS, result int) bool {
	record := info.ExceptionRecord
	mut context := info.ContextRecord
	if record.ExceptionCode != 0xc0000005 || record.ExceptionFlags != 0
		|| record.NumberParameters != 2 || record.ExceptionInformation[0] != 0
		|| record.ExceptionAddress != voidptr(context.Rip)
		|| record.ExceptionInformation[1] != context.Rcx { return false }
	signature := '\x8b\x01\xc3\x90VINIX'
	if unsafe { tos(&u8(record.ExceptionAddress), signature.len) } != signature { return false }
	mut memory := C.wine_memory_information{}
	if C.wine_virtual_query(voidptr(context.Rcx), &memory, sizeof(C.wine_memory_information)) == 0
		|| memory.Protect != 1 || memory.Type != 0x20000 { return false }
	context.Rax = u64(result)
	context.Rip += 2
	return true
}

fn exception_result(value i32) C.wine_exception_result {
	mut result := C.wine_exception_result{}
	unsafe { vmemcpy(&result, &value, int(sizeof(value))) }
	return result
}

fn exception_first(info &C.EXCEPTION_POINTERS) C.wine_exception_result {
	if software_exception(info, 1) || read_exception(info, 42) { return exception_result(-1) }
	return exception_result(0)
}

fn exception_last(info &C.EXCEPTION_POINTERS) C.wine_exception_result {
	if software_exception(info, 2) || read_exception(info, 84) { return exception_result(-1) }
	return exception_result(0)
}

fn vectored_exceptions(output voidptr) bool {
	if sizeof(C.wine_exception_result) != 4 { return false }
	// Two independent registrations distinguish search, priority and removal.
	mut last := C.AddVectoredExceptionHandler(0, exception_last)
	if last == unsafe { nil } { return false }
	defer { if last != unsafe { nil } { C.RemoveVectoredExceptionHandler(last) } }
	mut first := C.AddVectoredExceptionHandler(1, exception_first)
	if first == unsafe { nil } { return false }
	defer { if first != unsafe { nil } { C.RemoveVectoredExceptionHandler(first) } }
	mut order := ExceptionOrder{}
	mut arguments := [u64(unsafe { &order }), 0x56494e4958, 1]!
	C.RaiseException(0xe042564e, 0, 3, &arguments[0])
	if order.visits != 1 { return false }
	order.visits = 0
	arguments[2] = 2
	C.RaiseException(0xe042564e, 0, 3, &arguments[0])
	if order.visits != 12 { return false }
	page := C.VirtualAlloc(unsafe { nil }, 4096, 0x3000, 4)
	code := C.VirtualAlloc(unsafe { nil }, 4096, 0x3000, 4)
	defer {
		if page != unsafe { nil } { C.VirtualFree(page, 0, 0x8000) }
		if code != unsafe { nil } { C.VirtualFree(code, 0, 0x8000) }
	}
	if page == unsafe { nil } || code == unsafe { nil } { return false }
	instruction := '\x8b\x01\xc3\x90VINIX'
	unsafe { &u32(page)[0] = 17; vmemcpy(code, instruction.str, instruction.len) }
	mut old := C.DWORD(0)
	if !C.VirtualProtect(code, 4096, 0x20, &old) || old != 4 { return false }
	probe := unsafe { ReadProbe(code) }
	if probe(page) != 17 { return false }
	if !C.VirtualProtect(page, 4096, 1, &old) || old != 4 { return false }
	if probe(page) != 42 { return false }
	if C.RemoveVectoredExceptionHandler(first) == 0 { return false }
	first = unsafe { nil }
	order.visits = 0
	arguments[2] = 1
	C.RaiseException(0xe042564e, 0, 3, &arguments[0])
	if order.visits != 2 { return false }
	if !write(output, 'VINIX SIGNED WIN64 SOFTWARE EXCEPTION PASS\n') { return false }
	if probe(page) != 84 { return false }
	if C.RemoveVectoredExceptionHandler(last) == 0 { return false }
	last = unsafe { nil }
	return write(output, 'VINIX SIGNED WIN64 READ FAULT RECOVERY PASS\n')
}

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
	if !vectored_exceptions(output) { exit(30) }
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
