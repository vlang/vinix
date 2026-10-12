// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

import androidhost as ah
import androidrun
import cachecli
import crypto.rand
import encoding.base64
import hosttest
import os
import strconv
import time
import net.unix as _

#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
struct C.sockaddr_un { mut: sun_len u8 sun_family u16 sun_path [108]char }
struct C.pollfd { mut: fd i32 events i16 revents i16 }
fn C.poll(&C.pollfd, usize, i32) i32

struct AgentChannel {
mut:
 fd int = -1
 deadline u64
 cleanup bool
}

fn agent_connect(name string, cleanup bool) !AgentChannel {
 if name.len >= 104 || name.contains('\x00') { return error('invalid guest-agent socket path') }
 mut address := C.sockaddr_un{sun_family:u16(C.AF_UNIX)}
 $if macos { address.sun_len = u8(sizeof(C.sockaddr_un)) }
 unsafe { C.memcpy(&address.sun_path[0],name.str,usize(name.len)) }
 fd := C.socket(C.AF_UNIX,C.SOCK_STREAM,0)
 if fd < 0 { return os.error_posix() }
 mut channel := AgentChannel{fd:fd,deadline:time.sys_mono_now() + 30 * time.second,cleanup:cleanup}
 mut ready := false; defer { if !ready { channel.close() } }
 if C.fcntl(fd,C.F_SETFD,C.FD_CLOEXEC) != 0 || C.fcntl(fd,C.F_SETFL,C.O_NONBLOCK) != 0 { return os.error_posix() }
 $if macos {
  mut enabled := 1
  if C.setsockopt(fd,C.SOL_SOCKET,C.SO_NOSIGPIPE,&enabled,sizeof(int)) != 0 { return os.error_posix() }
 }
 for {
  if !cleanup { cachecli.checkpoint()! }
  if C.connect(fd,unsafe { voidptr(&address) },u32(sizeof(C.sockaddr_un))) == 0 { break }
  cause := C.errno
  if cause == C.EISCONN { break }
  if cause in [C.EINPROGRESS,C.EAGAIN,C.EWOULDBLOCK] {
   channel.ready(true)!
   mut pending := i32(0); mut length := u32(sizeof(i32))
   if C.getsockopt(fd,C.SOL_SOCKET,C.SO_ERROR,&pending,&length) != 0 { return os.error_posix() }
   if pending == 0 { break }
   if pending != C.ECONNREFUSED { return error_with_code(unsafe { C.strerror(pending).vstring().clone() },pending) }
  } else if cause != C.ECONNREFUSED { return os.error_posix() }
  if time.sys_mono_now() >= channel.deadline { return error('guest-agent connection timed out') }
  if cleanup { time.sleep(100 * time.millisecond) } else { pause(0.1)! }
 }
 ready = true
 return channel
}

fn (mut channel AgentChannel) close() {
 if channel.fd >= 0 { descriptor := channel.fd; channel.fd = -1; C.close(descriptor) }
}

fn (channel &AgentChannel) ready(writing bool) ! {
 mut descriptor := C.pollfd{fd:i32(channel.fd),events:i16(if writing { C.POLLOUT } else { C.POLLIN })}
 for {
  if !channel.cleanup { cachecli.checkpoint()! }
  if time.sys_mono_now() >= channel.deadline { return error('guest-agent socket timed out') }
  status := C.poll(&descriptor,1,50)
  if status > 0 { return }
  if status < 0 && C.errno != C.EINTR { return os.error_posix() }
 }
}

fn (mut channel AgentChannel) send(bytes []u8) ! {
 mut offset := 0
 for offset < bytes.len {
  channel.ready(true)!
  mut flags := 0; $if linux { flags = C.MSG_NOSIGNAL }
  count := unsafe { C.send(channel.fd,&u8(bytes.data) + offset,usize(bytes.len - offset),flags) }
  if count < 0 { if C.errno in [C.EAGAIN,C.EINTR] { continue }; return os.error_posix() }
  if count == 0 { return error('The guest agent closed the connection') }
  offset += int(count); channel.deadline = time.sys_mono_now() + 30 * time.second
 }
}

fn (mut channel AgentChannel) command(name string, args map[string]ah.Value) ! {
 channel.send((androidrun.dump_json(ah.Value({'execute':ah.Value(name),'arguments':ah.Value(args)}),-1) + '\n').bytes())!
}

fn (mut channel AgentChannel) read() !map[string]ah.Value {
 mut bytes := []u8{}; mut byte := u8(0)
 for {
  channel.ready(false)!
  count := C.recv(channel.fd,&byte,1,0)
  if count < 0 { if C.errno in [C.EAGAIN,C.EINTR] { continue }; return os.error_posix() }
  if count == 0 { return error('The guest agent closed the connection') }
  channel.deadline = time.sys_mono_now() + 30 * time.second
  if byte == `\n` {
   start := bytes.index(u8(`{`))
   if start >= 0 {
    text := bytes[start..].bytestr(); hosttest.module_decode_utf8(text)!
    value := androidrun.load_json(text)!
    if value !is map[string]ah.Value { return error('guest-agent reply is not an object') }
    return value.object()
   }
   bytes.clear()
  } else { bytes << byte }
  if bytes.len > 64 * 1024 * 1024 { return error('guest-agent reply too large') }
 }
 return error('The guest agent closed the connection')
}

pub struct Guest {
pub:
 socket string
}

pub fn (guest Guest) request(command string, arguments map[string]ah.Value) !ah.Value {
 return guest.request_policy(command,arguments,false)
}

fn (guest Guest) request_policy(command string, arguments map[string]ah.Value, cleanup bool) !ah.Value {
 mut channel := agent_connect(guest.socket,cleanup)!; defer { channel.close() }
 nonce := rand.int_u64(u64(1) << 32)!
 channel.send([u8(255)])!
 channel.command('guest-sync-delimited',{'id':ah.Value(nonce)})!
 for {
  reply := channel.read()!
  if ah.encode(ah.field(reply,'return')) == nonce.str() { break }
 }
 channel.command(command,arguments)!
 reply := channel.read()!
 if 'error' in reply { return error(androidrun.dump_json(reply['error']!,-1)) }
 return reply['return'] or { return error('guest-agent reply has no return') }
}

pub fn (guest Guest) execute(command string, timeout int) !int {
 launched := guest.request('guest-exec',{'path':ah.Value('/bin/sh'),'arg':ah.Value([ah.Value('-lc'),ah.Value(command)]),'capture-output':ah.Value(true)})!.object()
 pid := launched['pid'] or { return error('guest-exec reply has no PID') }
 deadline := time.sys_mono_now() + u64(if timeout > 0 { timeout } else { 0 }) * time.second
 for time.sys_mono_now() < deadline {
  result := guest.request('guest-exec-status',{'pid':pid})!.object()
  if ah.field(result,'exited') == ah.Value(true) {
   for field in ['out-data','err-data'] { print(replace_utf8(decode_base64(ah.field(result,field).text())!)) }
   flush_stdout()
   return if code := result['exitcode'] { strconv.atoi(ah.encode(code))! } else { -1 }
  }
  pause(0.5)!
 }
 return error('Guest command still running after ${timeout} seconds')
}

pub fn (guest Guest) transfer(guest_path string, host_path string, upload bool) ! {
 handle := guest.request('guest-file-open',{'path':ah.Value(guest_path),'mode':ah.Value(if upload { 'w' } else { 'r' })})!
 guest.transfer_body(handle,host_path,upload) or {
  failure := err
  guest.request_policy('guest-file-close',{'handle':handle},true)!
  return failure
 }
 guest.request_policy('guest-file-close',{'handle':handle},true)!
}

fn (guest Guest) transfer_body(handle ah.Value, host_path string, upload bool) ! {
 mut file := if upload { os.open(host_path)! } else { os.create(host_path)! }
 defer { file.close() }
 mut buffer := []u8{len:256 * 1024}
 for {
  if upload {
   count := file.read(mut buffer) or { if err is os.Eof { 0 } else { return err } }
   if count == 0 { break }
   response := guest.request('guest-file-write',{'handle':handle,'buf-b64':ah.Value(base64.encode(buffer[..count]))})!.object()
   if ah.encode(ah.field(response,'count')) != count.str() { return error('Short guest file write') }
  } else {
   response := guest.request('guest-file-read',{'handle':handle,'count':ah.Value(256 * 1024)})!.object()
   bytes := decode_base64(ah.field(response,'buf-b64').text())!
   mut position := 0
   for position < bytes.len { count := file.write(bytes[position..])!; if count <= 0 { return error('short host file write') }; position += count }
   if ah.field(response,'eof') == ah.Value(true) || ah.encode(ah.field(response,'count')) == '0' { break }
  }
 }
}

pub fn agent_cli(argv []string) !int {
 args := cachecli.arguments(argv,['--socket','--timeout'],[],[],1,-1,'Execute a command or transfer a file through KekVM guest agent.\nUsage: kekvm-control --socket PATH [--timeout 60] exec COMMAND | get GUEST HOST | put GUEST HOST') or { return error_with_code(err.msg(),2) }
 guest := Guest{socket:args.required('--socket') or { return error_with_code(err.msg(),2) }}
 action := args.positional[0]
 timeout := strconv.atoi(args.value('--timeout','60')) or { return error_with_code(err.msg(),2) }
 if action == 'exec' && args.positional.len == 2 { return guest.execute(args.positional[1],timeout) }
 if action in ['get','put'] && args.positional.len == 3 { guest.transfer(args.positional[1],args.positional[2],action == 'put')!; return 0 }
 return error_with_code('expected exec COMMAND, get GUEST HOST or put GUEST HOST',2)
}
