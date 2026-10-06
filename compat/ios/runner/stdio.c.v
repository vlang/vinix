// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.fopen(&char, &char) voidptr
fn C.fclose(voidptr) int
fn C.fflush(voidptr) int
fn C.fread(voidptr, usize, usize, voidptr) usize
fn C.fwrite(voidptr, usize, usize, voidptr) usize
fn C.fseek(voidptr, i64, int) int
fn C.ftell(voidptr) i64
fn C.fgetc(voidptr) int
fn C.fputc(int, voidptr) int
fn C.fgets(&char, int, voidptr) &char
fn C.fputs(&char, voidptr) int
fn C.feof(voidptr) int
fn C.ferror(voidptr) int
fn C.clearerr(voidptr)
fn C.fileno(voidptr) int
fn C.ungetc(int, voidptr) int
fn C.setvbuf(voidptr, &char, int, usize) int
fn C.tmpfile() voidptr
fn C.ios_vsnprintf(&char, usize, &char, voidptr) int
fn C.ios_vsprintf(&char, &char, voidptr) int
fn C.ios_vfprintf(voidptr, &char, voidptr) int
fn C.ios_vsscanf(&char, &char, voidptr) int
fn C.ios_printf()
fn C.ios_fprintf()
fn C.ios_sprintf()
fn C.ios_sscanf()
fn C.ios_asprintf()
fn C.ios_snprintf_checked()
fn C.ios_sprintf_checked()

fn stdio_native(file u64) voidptr {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return system_data.streams[file] or { panic('iOS: invalid Darwin FILE pointer') }
}

fn stdio_wrap(native voidptr) u64 {
	if native == unsafe { nil } { return 0 }
	file := C.calloc(1, 152)
	if file == unsafe { nil } { C.fclose(native); darwin_set_errno(12); return 0 }
	C.ios_objc_initialize_lock()
	system_data.streams[u64(file)] = native
	C.ios_objc_initialize_unlock()
	unsafe { *(&u16(u64(file) + 16)) = 0x10; *(&i16(u64(file) + 18)) = i16(C.fileno(native)) }
	return u64(file)
}

fn stdio_update(file u64, native voidptr) {
	mut flags := unsafe { *(&u16(file + 16)) } & ~u16(0x60)
	if C.feof(native) != 0 { flags |= 0x20 }
	if C.ferror(native) != 0 { flags |= 0x40 }
	unsafe { *(&u16(file + 16)) = flags }
	write32(file + 8, 0)
	write32(file + 12, 0)
}

fn darwin_fopen(path &char, mode &char) u64 { return stdio_wrap(C.fopen(path, mode)) }
fn darwin_tmpfile() u64 { return stdio_wrap(C.tmpfile()) }
fn darwin_fclose(file u64) int {
	native := stdio_native(file)
	C.ios_objc_initialize_lock()
	system_data.streams.delete(file)
	C.ios_objc_initialize_unlock()
	C.free(unsafe { voidptr(file) })
	return C.fclose(native)
}
fn darwin_fflush(file u64) int { return C.fflush(if file == 0 { unsafe { nil } } else { stdio_native(file) }) }
fn darwin_fread(buffer voidptr, size usize, count usize, file u64) usize {
	native := stdio_native(file)
	result := C.fread(buffer, size, count, native)
	stdio_update(file, native)
	return result
}
fn darwin_fwrite(buffer voidptr, size usize, count usize, file u64) usize {
	native := stdio_native(file)
	result := C.fwrite(buffer, size, count, native)
	stdio_update(file, native)
	return result
}
fn darwin_fseek(file u64, offset i64, whence int) int {
	native := stdio_native(file)
	result := C.fseek(native, offset, whence)
	stdio_update(file, native)
	return result
}
fn darwin_ftell(file u64) i64 { return C.ftell(stdio_native(file)) }
fn darwin_fgetc(file u64) int {
	native := stdio_native(file)
	result := C.fgetc(native)
	stdio_update(file, native)
	return result
}
fn darwin_fputc(value int, file u64) int {
	native := stdio_native(file)
	result := C.fputc(value, native)
	stdio_update(file, native)
	return result
}
fn darwin_fgets(buffer &char, count int, file u64) &char {
	native := stdio_native(file)
	result := C.fgets(buffer, count, native)
	stdio_update(file, native)
	return result
}
fn darwin_fputs(text &char, file u64) int { return C.fputs(text, stdio_native(file)) }
fn darwin_feof(file u64) int { return C.feof(stdio_native(file)) }
fn darwin_ferror(file u64) int { return C.ferror(stdio_native(file)) }
fn darwin_fileno(file u64) int { return C.fileno(stdio_native(file)) }
fn darwin_clearerr(file u64) {
	native := stdio_native(file)
	C.clearerr(native)
	stdio_update(file, native)
}
fn darwin_rewind(file u64) { darwin_fseek(file, 0, 0); darwin_clearerr(file) }
fn darwin_ungetc(value int, file u64) int {
	native := stdio_native(file)
	result := C.ungetc(value, native)
	stdio_update(file, native)
	return result
}
fn darwin_setvbuf(file u64, buffer &char, mode int, size usize) int { return C.setvbuf(stdio_native(file), buffer, mode, size) }
fn darwin_setbuf(file u64, buffer &char) { C.setvbuf(stdio_native(file), buffer, if buffer == unsafe { nil } { 2 } else { 0 }, 1024) }

@[export: 'ios_snprintf_stack']
fn darwin_vsnprintf(buffer &char, size usize, format &char, stack voidptr) int {
	return C.ios_vsnprintf(buffer, size, format, stack)
}
@[export: 'ios_sprintf_stack']
fn darwin_vsprintf(buffer &char, format &char, stack voidptr) int { return C.ios_vsprintf(buffer, format, stack) }
@[export: 'ios_printf_stack']
fn darwin_printf(format &char, stack voidptr) int { return C.ios_vfprintf(C.ios_host_stdio(1), format, stack) }
@[export: 'ios_fprintf_stack']
fn darwin_vfprintf(file u64, format &char, stack voidptr) int { return C.ios_vfprintf(stdio_native(file), format, stack) }
@[export: 'ios_sscanf_stack']
fn darwin_vsscanf(input &char, format &char, stack voidptr) int { return C.ios_vsscanf(input, format, stack) }

@[export: 'ios_asprintf_stack']
fn darwin_vasprintf(output &&char, format &char, stack voidptr) i32 {
	if output == unsafe { nil } { darwin_set_errno(22); return -1 }
	unsafe { *output = nil }
	length := C.ios_vsnprintf(unsafe { nil }, 0, format, stack)
	if length < 0 { return -1 }
	buffer := C.malloc(usize(length) + 1)
	if buffer == unsafe { nil } { darwin_set_errno(12); return -1 }
	result := C.ios_vsnprintf(buffer, usize(length) + 1, format, stack)
	if result < 0 || result > length { C.free(buffer); return -1 }
	unsafe { *output = &char(buffer) }
	return i32(result)
}

@[export: 'ios_snprintf_checked_stack']
fn darwin_vsnprintf_checked(buffer &char, size usize, flag i32, capacity usize, format &char, stack voidptr) i32 {
	_ = flag
	if size > capacity { panic('iOS: fortified snprintf exceeds destination') }
	return i32(C.ios_vsnprintf(buffer, size, format, stack))
}

@[export: 'ios_sprintf_checked_stack']
fn darwin_vsprintf_checked(buffer &char, flag i32, capacity usize, format &char, stack voidptr) i32 {
	_ = flag
	result := C.ios_vsnprintf(buffer, capacity, format, stack)
	if result >= 0 && usize(result) >= capacity { panic('iOS: fortified sprintf exceeds destination') }
	return i32(result)
}

fn stdio_symbol(symbol string) ?u64 {
	return match symbol {
		'_fopen', '_fopen$DARWIN_EXTSN' { u64(unsafe { voidptr(darwin_fopen) }) }
		'_tmpfile' { u64(unsafe { voidptr(darwin_tmpfile) }) }
		'_fclose' { u64(unsafe { voidptr(darwin_fclose) }) }
		'_fflush' { u64(unsafe { voidptr(darwin_fflush) }) }
		'_fread' { u64(unsafe { voidptr(darwin_fread) }) }
		'_fwrite' { u64(unsafe { voidptr(darwin_fwrite) }) }
		'_fseek', '_fseeko' { u64(unsafe { voidptr(darwin_fseek) }) }
		'_ftell', '_ftello' { u64(unsafe { voidptr(darwin_ftell) }) }
		'_fgetc', '_getc', '___srget' { u64(unsafe { voidptr(darwin_fgetc) }) }
		'_fputc', '_putc', '___swbuf' { u64(unsafe { voidptr(darwin_fputc) }) }
		'_fgets' { u64(unsafe { voidptr(darwin_fgets) }) }
		'_fputs' { u64(unsafe { voidptr(darwin_fputs) }) }
		'_feof' { u64(unsafe { voidptr(darwin_feof) }) }
		'_ferror' { u64(unsafe { voidptr(darwin_ferror) }) }
		'_fileno' { u64(unsafe { voidptr(darwin_fileno) }) }
		'_clearerr' { u64(unsafe { voidptr(darwin_clearerr) }) }
		'_rewind' { u64(unsafe { voidptr(darwin_rewind) }) }
		'_ungetc' { u64(unsafe { voidptr(darwin_ungetc) }) }
		'_setvbuf' { u64(unsafe { voidptr(darwin_setvbuf) }) }
		'_setbuf' { u64(unsafe { voidptr(darwin_setbuf) }) }
		'_printf' { u64(unsafe { voidptr(C.ios_printf) }) }
		'_fprintf' { u64(unsafe { voidptr(C.ios_fprintf) }) }
		'_sprintf' { u64(unsafe { voidptr(C.ios_sprintf) }) }
		'_sscanf' { u64(unsafe { voidptr(C.ios_sscanf) }) }
		'_snprintf' { u64(unsafe { voidptr(C.ios_snprintf) }) }
		'_vsnprintf' { u64(unsafe { voidptr(darwin_vsnprintf) }) }
		'_vsprintf' { u64(unsafe { voidptr(darwin_vsprintf) }) }
		'_vfprintf' { u64(unsafe { voidptr(darwin_vfprintf) }) }
		'_vsscanf' { u64(unsafe { voidptr(darwin_vsscanf) }) }
		'_asprintf' { u64(unsafe { voidptr(C.ios_asprintf) }) }
		'_vasprintf' { u64(unsafe { voidptr(darwin_vasprintf) }) }
		'___snprintf_chk' { u64(unsafe { voidptr(C.ios_snprintf_checked) }) }
		'___vsnprintf_chk' { u64(unsafe { voidptr(darwin_vsnprintf_checked) }) }
		'___sprintf_chk' { u64(unsafe { voidptr(C.ios_sprintf_checked) }) }
		'___vsprintf_chk' { u64(unsafe { voidptr(darwin_vsprintf_checked) }) }
		else { return none }
	}
}
