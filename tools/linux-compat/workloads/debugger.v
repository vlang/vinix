// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import net
import os
import strconv
import time

struct DebugResult {
 argv []string
 executable_sha256 string
 runtime_probe_sha256 string
 initial_pc u64
 stepped_pc u64
 registers_sha256 string
 memory_address u64
 memory_hex string
 breakpoint_hit bool
 memory_restored bool
 exit_code int
 stdout string
 stderr string
 retired bool
}

fn rsp_hex(value u8) string {
 alphabet := '0123456789abcdef'
 return [alphabet[value >> 4], alphabet[value & 15]].bytestr()
}

fn rsp_byte(mut conn net.TcpConn) !u8 {
 mut byte := [1]u8{}
 if conn.read(mut byte)! != 1 { return error('debugger connection closed') }
 return byte[0]
}

fn rsp_query(mut conn net.TcpConn, request string) !string {
 mut checksum := u8(0)
 for byte in request { checksum += byte }
 conn.write_string('$' + request + '#' + rsp_hex(checksum))!
 for {
  byte := rsp_byte(mut conn)!
  if byte == `$` { break }
  if byte != `+` { return error('unexpected debugger acknowledgement') }
 }
 mut wire := []u8{}
 checksum = 0
 for {
  byte := rsp_byte(mut conn)!
  if byte == `#` { break }
  if wire.len >= 65536 { return error('debugger packet exceeded limit') }
  checksum += byte
  wire << byte
 }
 received := [rsp_byte(mut conn)!, rsp_byte(mut conn)!].bytestr()
 if received != rsp_hex(checksum) { return error('debugger packet checksum mismatch') }
 conn.write_string('+')!
 mut decoded := []u8{}
 mut index := 0
 for index < wire.len {
  byte := wire[index]
  index++
  if byte == `}` {
   if index == wire.len { return error('truncated escaped debugger packet') }
   decoded << wire[index] ^ u8(0x20)
   index++
  } else if byte == `*` {
   if decoded.len == 0 || index == wire.len || wire[index] < 29 { return error('invalid debugger repetition') }
   count := int(wire[index]) - 29
   index++
   previous := decoded.last()
   for _ in 0 .. count { decoded << previous }
  } else { decoded << byte }
  if decoded.len > 65536 { return error('decoded debugger packet exceeded limit') }
 }
 return decoded.bytestr()
}

fn rsp_register(registers string, number int, width int) !u64 {
 offset := number * width * 2
 if registers.len < offset + width * 2 { return error('incomplete x86 register packet') }
 mut value := u64(0)
 for index in 0 .. width {
  byte := strconv.parse_uint(registers[offset + index * 2..offset + index * 2 + 2], 16, 8)!
  value |= byte << (index * 8)
 }
 return value
}

fn rsp_pc(registers string, path string) !u64 {
 // QEMU's x86 core register order: 16 64-bit GPRs then RIP, or 8
 // 32-bit GPRs then EIP. The remaining SIMD registers are opaque here.
 return rsp_register(registers, if path == 'translated-i386' { 8 } else { 16 },
  if path == 'translated-i386' { 4 } else { 8 })
}

fn stopped_on_trap(reply string) bool {
 return reply.starts_with('T05') || reply == 'S05'
}

fn (mut suite Suite) debug_runtime() ! {
 if !suite.path.starts_with('translated-') {
  return error('unsupported: native ptrace has no syscall dispatch; translated debugging uses the QEMU GDB remote stub')
 }
 if suite.runtime == '' { return error('unsupported: supply the matching runtime probe') }
 mut argv := suite.command(suite.runtime, ['--once'])!
 // A musl wrapper cannot expose its child's remote stub. Use the native
 // translator directly with the same private runtime and launch policy.
 if suite.path == 'translated-x86_64' && suite.runtime_libc == 'musl' {
  emulator := os.getenv_opt('VINIX_X86_64_EMULATOR') or { '/usr/bin/qemu-x86_64' }
  if !os.is_executable(emulator) { return error('unsupported: missing native translator') }
  argv = [emulator, '-B', os.getenv_opt('VINIX_X86_64_GUEST_BASE') or { '0x100000000' },
   '-L', os.getenv_opt('VINIX_X86_64_ROOT') or { '/usr/libexec/vinix-x86_64/root' }, suite.runtime, '--once']
 }
 argv.insert(1, ['-g', '19016'])
 emulator_hash := sha256.sum(os.read_bytes(argv[0])!).hex()
 probe_hash := sha256.sum(os.read_bytes(suite.runtime)!).hex()
 mut child := os.new_process(argv[0])
 child.set_args(argv[1..])
 mut environment := os.environ()
 environment['VINIX_ALLOW_WX'] = '1'
 for name in ['LD_LIBRARY_PATH', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV'] { environment.delete(name) }
 child.set_environment(environment)
 child.set_work_folder(suite.work)
 child.set_redirect_stdio()
 child.use_pgroup = true
 child.run()
 mut initial_pc := u64(0)
 mut stepped_pc := u64(0)
 mut registers_hash := ''
 mut memory_address := u64(0)
 mut memory := ''
 mut breakpoint_hit := false
 mut restored := false
 mut out := ''
 mut stderr_text := ''
 defer {
  stop(mut child)
  suite.debuggers << DebugResult{argv, emulator_hash, probe_hash, initial_pc,
   stepped_pc, registers_hash, memory_address, memory, breakpoint_hit, restored, child.code,
   out, stderr_text, !child.is_alive()}
 }
 watch := time.new_stopwatch()
 mut conn := net.TcpConn{}
 for {
  if !child.is_alive() { return error('translator exited before debugger readiness') }
  conn = net.dial_tcp('127.0.0.1:19016') or {
   if watch.elapsed() > 5 * time.second { return error('debugger was not ready after five seconds') }
   time.sleep(20 * time.millisecond)
   continue
  }
  break
 }
 defer { conn.close() or {} }
 conn.set_read_timeout(5 * time.second)
 conn.set_write_timeout(5 * time.second)
 rsp_query(mut conn, 'qSupported')!
 expect(stopped_on_trap(rsp_query(mut conn, '?')!), 'debugger did not start stopped')!
 registers := rsp_query(mut conn, 'g')!
 registers_hash = sha256.sum(registers.bytes()).hex()
 initial_pc = rsp_pc(registers, suite.path)!
 expect(initial_pc != 0, 'debugger reported a null instruction pointer')!
 address := initial_pc.hex()
 expect(rsp_query(mut conn, 'm' + address + ',1')!.len == 2, 'debugger could not read instruction memory')!
 // QEMU-user respects page write permissions for remote memory writes.
 // Mutate and restore a stack byte, then prove execution remains intact.
 memory_address = rsp_register(registers, if suite.path == 'translated-i386' { 4 } else { 7 },
  if suite.path == 'translated-i386' { 4 } else { 8 })!
 data_address := memory_address.hex()
 memory = rsp_query(mut conn, 'm' + data_address + ',1')!
 expect(memory.len == 2, 'debugger could not read stack memory')!
 original := strconv.parse_uint(memory, 16, 8)!
 changed := rsp_hex(u8(original) ^ u8(1))
 expect(rsp_query(mut conn, 'M' + data_address + ',1:' + changed)! == 'OK', 'debugger memory write failed')!
 expect(rsp_query(mut conn, 'm' + data_address + ',1')! == changed, 'debugger memory write was not visible')!
 expect(rsp_query(mut conn, 'M' + data_address + ',1:' + memory)! == 'OK', 'debugger memory restore failed')!
 restored = rsp_query(mut conn, 'm' + data_address + ',1')! == memory
 expect(restored, 'debugger changed stack memory')!
 expect(rsp_query(mut conn, 'Z0,' + address + ',1')! == 'OK', 'debugger software breakpoint was rejected')!
 breakpoint_hit = stopped_on_trap(rsp_query(mut conn, 'c')!)
 expect(breakpoint_hit && rsp_pc(rsp_query(mut conn, 'g')!, suite.path)! == initial_pc,
  'debugger did not stop on the software breakpoint')!
 expect(rsp_query(mut conn, 'z0,' + address + ',1')! == 'OK', 'debugger breakpoint removal failed')!
 expect(stopped_on_trap(rsp_query(mut conn, 's')!), 'debugger single step did not trap')!
 stepped_pc = rsp_pc(rsp_query(mut conn, 'g')!, suite.path)!
 expect(stepped_pc != initial_pc && stepped_pc != 0, 'single stepping did not advance execution')!
 expect(rsp_query(mut conn, 'c')! == 'W00', 'debugged runtime did not exit successfully')!
 child.wait()
 for child.is_pending(.stdout) {
  block := child.stdout_read()
  if block == '' { break }
  out += block
  if out.len > 65536 { return error('debugged runtime output exceeded limit') }
 }
 for child.is_pending(.stderr) {
  block := child.stderr_read()
  if block == '' { break }
  stderr_text += block
  if stderr_text.len > 65536 { return error('debugged runtime errors exceeded limit') }
 }
 expect(child.code == 0 && out.contains('LINUX RUNTIME: PASS'), 'debugged runtime predicates did not pass')!
}
