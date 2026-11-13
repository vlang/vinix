// SPDX-License-Identifier: GPL-2.0-or-later
// A real Win64 executable. Only Wine can execute these Windows API calls.
module main

#include <windows.h>
fn C.GetStdHandle(u32) voidptr
fn C.WriteFile(voidptr, voidptr, u32, voidptr, voidptr) int
fn C.GetEnvironmentVariableA(&char, &char, u32) u32
fn C.CreateFileA(&char, u32, u32, voidptr, u32, u32, voidptr) voidptr
fn C.CloseHandle(voidptr) int
fn C.MapViewOfFile(voidptr, u32, u32, u32, u64) voidptr
fn C.UnmapViewOfFile(voidptr) int
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.GetCommandLineA() &char
@[typedef]
struct C.STARTUPINFOA { mut: cb u32 }
@[typedef]
struct C.PROCESS_INFORMATION { hProcess voidptr hThread voidptr }
fn C.CreateProcessA(&char, &char, voidptr, voidptr, int, u32, voidptr, &char, &C.STARTUPINFOA, &C.PROCESS_INFORMATION) int
fn C.WaitForSingleObject(voidptr, u32) u32
fn C.GetExitCodeProcess(voidptr, &C.DWORD) int
fn C.TerminateProcess(voidptr, u32) int
fn C.GetLastError() u32
fn C.GetFileAttributesA(&char) u32
fn C.Sleep(u32)
fn C.GetModuleHandleA(&char) voidptr
fn C.GetProcAddress(voidptr, &char) voidptr
fn C.VirtualFree(voidptr, C.ptrdiff_t, u32) bool
#define wine_memory_information MEMORY_BASIC_INFORMATION
#define wine_virtual_query VirtualQuery
@[typedef]
struct C.wine_memory_information {
	BaseAddress voidptr
	AllocationBase voidptr
	RegionSize u64
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

struct UserUnicodeName { length u16 maximum u16 buffer &u16 }
struct UserObjectAttributes {
	length u32
	root voidptr
	name &UserUnicodeName
	attributes u32
	security voidptr
	quality voidptr
}
type OpenUserSection = fn (voidptr, u32, &UserObjectAttributes) i32

fn dispatcher_child() bool {
	word := unsafe { &u32(0x7ffe4800) }
	if C.__atomic_load_n(word, 2) != 0 { return false }
	C.__atomic_store_n(word, 0x4348494c, 3)
	return true
}

fn private_dispatcher(output voidptr) bool {
	word := unsafe { &u32(0x7ffe4800) }
	if C.__atomic_load_n(word, 2) != 0 { return false }
	C.__atomic_store_n(word, 0x50415245, 3)
	defer { C.__atomic_store_n(word, 0, 3) }
	mut path := [4096]u8{}
	length := C.GetEnvironmentVariableA(c'VINIX_APP_DIR', &char(&path[0]), u32(path.len))
	if length == 0 || length >= u32(path.len) { return false }
	directory := unsafe { tos(&path[0], int(length)) }
	if !directory.starts_with('/') || directory.contains('"') || directory.contains('\\') { return false }
	// The SDK supplies the admitted immutable application path. Wine's
	// translated main-module name can instead use its internal "unix" form,
	// which CreateProcess cannot reopen as a DOS filename.
	name := 'Z:' + directory.replace('/', '\\') + '\\bin\\program.exe'
	defer { unsafe { name.free() } }
	if C.GetFileAttributesA(name.str) == u32(0xffffffff) { write(output, 'VINIX PRIVATE DISPATCH signed child image unavailable\n'); return false }
	command := '"' + name + '" --vinix-dispatch-child'
	defer { unsafe { command.free() } }
	mut startup := C.STARTUPINFOA{cb: u32(sizeof(C.STARTUPINFOA))}
	mut process := C.PROCESS_INFORMATION{}
	if C.CreateProcessA(name.str, command.str, unsafe { nil }, unsafe { nil }, 0, 0, unsafe { nil }, unsafe { nil }, &startup, &process) == 0 { write(output, 'VINIX PRIVATE DISPATCH child creation failed error=' + C.GetLastError().str() + '\n'); return false }
	defer { C.CloseHandle(process.hThread); C.CloseHandle(process.hProcess) }
	if C.WaitForSingleObject(process.hProcess, 10000) != 0 { write(output, 'VINIX PRIVATE DISPATCH child wait failed\n'); C.TerminateProcess(process.hProcess, 34); C.WaitForSingleObject(process.hProcess, 1000); return false }
	mut status := C.DWORD(99)
	ok := C.GetExitCodeProcess(process.hProcess, &status) != 0 && status == 0 && C.__atomic_load_n(word, 2) == 0x50415245
	if !ok { write(output, 'VINIX PRIVATE DISPATCH child status=' + u32(status).str() + ' parent=' + C.__atomic_load_n(word, 2).str() + '\n') }
	return ok
}

// Use the unused tail of this private 16 KiB section, never an architectural
// KUSER field. All views must agree before and after two distinct writes.
// Preserve the original word, including on a failed check; do not assume zero.
fn shared_user_data(output voidptr) bool {
	if sizeof(UserUnicodeName) != 16 || sizeof(UserObjectAttributes) != 48 { return false }
	mut initialized := false
	for _ in 0 .. 200 {
		if C.__atomic_load_n(unsafe { &u32(0x7ffe0308) }, 2) == 1
			&& C.__atomic_load_n(unsafe { &u32(0x7ffe026c) }, 2) != 0 { initialized = true; break }
		C.Sleep(10)
	}
	if !initialized {
		write(output, 'VINIX SHARED USER DATA initialization refused system=' + C.__atomic_load_n(unsafe { &u32(0x7ffe0308) }, 2).str() + ' major=' + C.__atomic_load_n(unsafe { &u32(0x7ffe026c) }, 2).str() + '\n')
		return false
	}
	module_handle := C.GetModuleHandleA(c'ntdll.dll')
	address := C.GetProcAddress(module_handle, c'NtOpenSection')
	if address == unsafe { nil } { return false }
	open_section := unsafe { OpenUserSection(address) }
	wide := '\\KernelObjects\\__wine_user_shared_data'.to_wide()
	defer { unsafe { free(wide) } }
	mut name := UserUnicodeName{length: 76, maximum: 78, buffer: wide}
	mut attributes := UserObjectAttributes{length: 48, root: unsafe { nil }, name: &name, attributes: 0x40, security: unsafe { nil }, quality: unsafe { nil }}
	mut handle := unsafe { nil }
	status := open_section(&handle, 6, &attributes)
	if status < 0 || handle == unsafe { nil } { write(output, 'VINIX SHARED USER DATA open refused status=' + status.str() + '\n'); return false }
	defer { C.CloseHandle(handle) }
	view := C.MapViewOfFile(handle, 6, 0, 0, 16384)
	if view == unsafe { nil } { write(output, 'VINIX SHARED USER DATA writer mapping refused\n'); return false }
	defer { C.UnmapViewOfFile(view) }
	mut mapped_info := C.wine_memory_information{}
	mut fixed_info := C.wine_memory_information{}
	if C.wine_virtual_query(view, &mapped_info, sizeof(C.wine_memory_information)) == 0
		|| C.wine_virtual_query(voidptr(0x7ffe1000), &fixed_info, sizeof(C.wine_memory_information)) == 0 { return false }
	write(output, 'VINIX SHARED USER DATA mappings writer=' + u64(view).str() + ' protect=' + mapped_info.Protect.str() + ' type=' + mapped_info.Type.str() + ' extent=' + mapped_info.RegionSize.str() + ' fixed-protect=' + fixed_info.Protect.str() + ' fixed-extent=' + fixed_info.RegionSize.str() + '\n')
	if mapped_info.Protect != 4 || fixed_info.Protect != 2 { return false }
	other := C.MapViewOfFile(handle, 6, 0, 0, 16384)
	if other == unsafe { nil } { return false }
	defer { C.UnmapViewOfFile(other) }
	mut saved := [4]u32{}
	for page in 0 .. 4 {
		offset := u64(page * 4096 + 0x800)
		saved[page] = C.__atomic_load_n(unsafe { &u32(u64(view) + offset) }, 2)
		if C.__atomic_load_n(unsafe { &u32(u64(0x7ffe0000) + offset) }, 2) != saved[page]
			|| C.__atomic_load_n(unsafe { &u32(u64(other) + offset) }, 2) != saved[page] { return false }
		mut info := C.wine_memory_information{}
		if C.wine_virtual_query(voidptr(u64(0x7ffe0000) + offset), &info, sizeof(C.wine_memory_information)) == 0 || info.Protect != 2 { return false }
	}
	defer { for page in 0 .. 4 { C.__atomic_store_n(unsafe { &u32(u64(view) + u64(page * 4096 + 0x800)) }, saved[page], 3) } }
	for page in 0 .. 4 {
		for reverse in [false, true]! {
			value := saved[page] ^ if reverse { u32(0x584e4956) } else { u32(0x56494e58) }
			base := if reverse { other } else { view }
			C.__atomic_store_n(unsafe { &u32(u64(base) + u64(page * 4096 + 0x800)) }, value, 3)
			for index in 0 .. 4 {
				wanted := if index == page { value } else { saved[index] }
				for alias in [view, other, voidptr(0x7ffe0000)]! {
					if C.__atomic_load_n(unsafe { &u32(u64(alias) + u64(index * 4096 + 0x800)) }, 2) != wanted { return false }
				}
			}
			C.__atomic_store_n(unsafe { &u32(u64(view) + u64(page * 4096 + 0x800)) }, saved[page], 3)
		}
	}
	return true
}

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

// Explicit local lifetime probe; ordinary Win64 qualification stays unchanged.
fn collection_probe(child bool) bool {
	output := C.GetStdHandle(u32(0xfffffff5))
	if child {
		if !write(output, 'VINIX COLLECTION CHILD READY\n') { return false }
		for _ in 0 .. 30000 {
			if C.GetFileAttributesA(c'C:\\users\\vinix\\Temp\\collection-release') != u32(0xffffffff) {
				return write(output, 'VINIX COLLECTION CHILD RETIRED\n')
			}
			C.Sleep(10)
		}
		return false
	}
	if !write(output, 'VINIX COLLECTION INITIAL READY\n') { return false }
	// Give the native observer a bounded initial-client identity window.
	C.Sleep(3000)
	mut path := [4096]u8{}
	length := C.GetEnvironmentVariableA(c'VINIX_APP_DIR', &char(&path[0]), u32(path.len))
	if length == 0 || length >= u32(path.len) { return false }
	directory := unsafe { tos(&path[0], int(length)) }
	if !directory.starts_with('/') || directory.contains('"') || directory.contains('\\') { return false }
	name := 'Z:' + directory.replace('/', '\\') + '\\bin\\program.exe'
	command := '"' + name + '" --vinix-collection-child'
	defer { unsafe { name.free(); command.free() } }
	mut startup := C.STARTUPINFOA{cb: u32(sizeof(C.STARTUPINFOA))}
	mut process := C.PROCESS_INFORMATION{}
	if C.CreateProcessA(name.str, command.str, unsafe { nil }, unsafe { nil }, 1, 0,
		unsafe { nil }, unsafe { nil }, &startup, &process) == 0 { return false }
	C.CloseHandle(process.hThread)
	C.CloseHandle(process.hProcess)
	return true
}

fn main() {
	if !variable(c'VINIX_APP_ID', 'org.vinix.wine-win64-probe') || !variable(c'VINIX_APP_KIND', 'windows') ||
		!variable(c'VINIX_APP_RUNTIME_ID', 'org.vinix.wine-runtime') || !variable(c'USER', 'vinix') ||
		!variable(c'WINEARCH', 'win64') { exit(21) }
	command_line := C.GetCommandLineA()
	if command_line != unsafe { nil } {
		line := unsafe { cstring_to_vstring(command_line) }
		if line.ends_with(' --vinix-collection-child') {
			if !collection_probe(true) { exit(39) }
			exit(0)
		}
		if line.ends_with(' --vinix-collection-probe') {
			if !collection_probe(false) { exit(38) }
			exit(37)
		}
	}
	if command_line != unsafe { nil } && unsafe { cstring_to_vstring(command_line) }.ends_with(' --vinix-dispatch-child') {
		if !dispatcher_child() { exit(34) }
		exit(0)
	}
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
	if !shared_user_data(output) { exit(31) }
	if !write(output, 'VINIX SIGNED WIN64 SHARED USER DATA PASS\n') { exit(32) }
	if !private_dispatcher(output) { exit(35) }
	if !write(output, 'VINIX SIGNED WIN64 PRIVATE DISPATCH PAGE PASS\n') { exit(36) }
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
