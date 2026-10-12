// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidhost as ah
import cachecli
import encoding.base64
import gamehost
import json2
import net.unix
import os
import time

#include <fcntl.h>
#include <sys/un.h>
struct C.sockaddr_un { mut: sun_len u8 sun_family u16 sun_path [108]char }
fn C.getdtablesize() int

fn read_line(mut connection unix.StreamConn) !map[string]ah.Value {
 mut bytes := []u8{}; mut byte := []u8{len:1}
 for { if connection.read(mut byte)! == 0 { return error('EOF') }; if byte[0] == `\n` { break }; bytes << byte[0] }
 if bytes.len > 0 && bytes[0] == 255 { bytes.delete(0) }
 return json2.decode[ah.Value](bytes.bytestr(),strict:true)!.object()
}

fn serve(socket string, mode string, data []u8, ready string) ! {
 mut listener := unix.listen_stream(socket)!; defer { listener.close() or {} }
 os.write_file(ready,'ready')!
 expected := match mode { 'execute' { 3 } 'put','get' { 5 } 'short','read-error','cancel' { 3 } 'host-error' { 2 } else { 1 } }
 mut received := []u8{}; mut offset := 0; mut closes := 0
 for index in 0 .. expected {
  mut connection := listener.accept()!
  connection.set_read_timeout(5 * time.second)
  sync := read_line(mut connection)!
  assert ah.field(sync,'execute').text() == 'guest-sync-delimited'
  nonce := ah.encode(ah.field(ah.field(sync,'arguments').object(),'id'))
  assert nonce.u64() < u64(1) << 32
  // Include data left over from the previous guest-agent client.
  connection.write_string('garbage without JSON\n{"return":"stale"}\n\xff{"return":${nonce}}\n')!
  request := read_line(mut connection)!
  command := ah.field(request,'execute').text(); args := ah.field(request,'arguments').object()
  mut response := '{"return":{}}\n'
  match command {
   'guest-exec' {
    assert ah.field(args,'path').text() == '/bin/sh'
    assert ah.field(args,'arg').items().map(it.text()) == ['-lc','printf "fixture"']
    assert ah.field(args,'capture-output') == ah.Value(true)
    response = '{"return":{"pid":100000000000000000000}}\n'
   }
   'guest-exec-status' {
    assert ah.encode(ah.field(args,'pid')) == '100000000000000000000'
    response = if index == 1 { '{"return":{"exited":false}}\n' } else { '{"return":{"exited":true,"exitcode":7,"out-data":"b2sK","err-data":"/w=="}}\n' }
   }
   'guest-file-open' {
    assert ah.field(args,'path').text() == '/guest literal "é"'
    assert ah.field(args,'mode').text() == if mode in ['put','short','host-error','cancel'] { 'w' } else { 'r' }
    response = '{"return":98765432109876543210987654321}\n'
   }
   'guest-file-write' {
    assert ah.encode(ah.field(args,'handle')) == '98765432109876543210987654321'
    decoded := base64.decode(ah.field(args,'buf-b64').text())
    assert decoded.len <= 256 * 1024 && decoded.len > 0
    received << decoded
    if mode == 'cancel' { assert C.kill(os.getpid(),C.SIGINT) == 0 }
    response = '{"return":{"count":${if mode == 'short' { 1 } else { decoded.len }}}}\n'
   }
   'guest-file-read' {
    assert ah.encode(ah.field(args,'handle')) == '98765432109876543210987654321'
    assert ah.encode(ah.field(args,'count')) == '262144'
    limit := if data.len - offset > 256 * 1024 { 256 * 1024 } else { data.len - offset }
    encoded := base64.encode(data[offset..offset + limit]); offset += limit
    response = if mode == 'read-error' { '{"error":{"desc":"controlled read failure"}}\n' } else { '{"return":{"count":${limit},"buf-b64":"${encoded}","eof":${offset == data.len}}}\n' }
   }
   'guest-file-close' { closes++ }
   'fixture' {
    response = match mode {
     'wide' { '{"return":-123456789012345678901234567890}\n' }
     'error' { '{"return":0,"error":{"desc":"error takes precedence"}}\n' }
     'malformed' { '\xff{"return":}\n' }
     'eof' { '' }
     else { return error('unknown fixture mode') }
    }
   }
   else { return error('unexpected command: ' + command) }
  }
  if response != '' { connection.write_string(response) or { if mode != 'cancel' { return err }; 0 } }
  connection.close()!
 }
 if mode == 'put' { assert received == data }
 if mode in ['put','get','short','host-error','read-error','cancel'] { assert closes == 1 }
}

fn delayed_serve(socket string, data []u8, ready string) ! {
 time.sleep(200 * time.millisecond)
 serve(socket,'wide',data,ready)!
}

fn descriptors() int {
 mut count := 0
 for fd in 0 .. C.getdtablesize() { if C.fcntl(fd,C.F_GETFD) >= 0 { count++ } }
 return count
}

fn main() {
 guard := cachecli.own_commands(); defer { guard.close() }
 if os.args.len != 2 { exit(2) }
 work := os.args[1]; gamehost.mkdir(work) or { panic(err) }
 data := []u8{len:600001,init:u8(index % 251)}
 os.write_file_array(work + '/source',data) or { panic(err) }
 for mode in ['execute','put','get','short','host-error','read-error','wide','error','malformed','eof'] {
  socket := work + '/' + mode; ready := socket + '.ready'
  server := spawn serve(socket,mode,data,ready)
  deadline := time.sys_mono_now() + 5 * time.second
  for !os.exists(ready) { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
  guest := gamehost.Guest{socket:socket}
  mut refused := false
  match mode {
   'execute' { assert guest.execute('printf "fixture"',5) or { panic(err) } == 7 }
   'put','short','host-error' {
    guest.transfer('/guest literal "é"',if mode == 'host-error' { work + '/absent/source' } else { work + '/source' },true) or { refused = true }
   }
   'get','read-error' {
    guest.transfer('/guest literal "é"',work + '/destination',false) or { refused = true }
    if mode == 'get' { assert os.read_bytes(work + '/destination') or { panic(err) } == data }
   }
   else {
    response := guest.request('fixture',{}) or { refused = true; ah.Value(0) }
    if mode == 'wide' { assert ah.encode(response) == '-123456789012345678901234567890' }
   }
  }
  server.wait() or { panic(err) }
  assert refused == (mode in ['short','host-error','read-error','error','malformed','eof'])
  if os.exists(socket) { os.rm(socket) or { panic(err) } }
 }
 baseline := descriptors()
 for _ in 0 .. 100 { guest := gamehost.Guest{socket:work + '/absent.sock'}; guest.request('fixture',{}) or { continue }; panic('absent socket accepted') }
 assert descriptors() == baseline
 {
  socket_path := work + '/retry'; mut address := C.sockaddr_un{sun_family:u16(C.AF_UNIX)}
  $if macos { address.sun_len = u8(sizeof(C.sockaddr_un)) }
  unsafe { C.memcpy(&address.sun_path[0],socket_path.str,usize(socket_path.len)) }
  descriptor := C.socket(C.AF_UNIX,C.SOCK_STREAM,0); assert descriptor >= 0
  assert C.bind(descriptor,unsafe { voidptr(&address) },u32(sizeof(C.sockaddr_un))) == 0
  assert C.close(descriptor) == 0
  server := spawn delayed_serve(socket_path,data,socket_path + '.ready')
  guest := gamehost.Guest{socket:socket_path}
  assert ah.encode(guest.request('fixture',{}) or { panic(err) }) == '-123456789012345678901234567890'
  server.wait() or { panic(err) }
 }
 {
  socket := work + '/cancel'; ready := socket + '.ready'
  server := spawn serve(socket,'cancel',data,ready)
  for !os.exists(ready) { time.sleep(time.millisecond) }
  guest := gamehost.Guest{socket:socket}
  mut refused := false
  guest.transfer('/guest literal "é"',work + '/source',true) or { refused = true }
  server.wait() or { panic(err) }
  assert refused && cachecli.cancelled()
  reset := cachecli.own_commands(); reset.close()
 }
 for encoded, decoded in {'':'','YQ==':'a','YWI=':'ab','YWJj':'abc','! Y W J j \n':'abc','===YQ==after':'a','YWJj=':'abc'} { assert gamehost.decode_base64(encoded) or { panic(err) }.bytestr() == decoded }
 for encoded in ['Y','YQ','YQ=','YWI','YWJjY','é'] {
  mut refused := false; gamehost.decode_base64(encoded) or { refused = true }; assert refused
 }
 os.write_file(work + '/passed','PASS\n') or { panic(err) }
 eprintln('NATIVE KEKVM AGENT / real socket nonce and stale-prefix sync, wide IDs, command polling/status, 600001-byte transfers, short/error/finally close, malformed/EOF, 100 failed constructor descriptor owners: PASS')
}
