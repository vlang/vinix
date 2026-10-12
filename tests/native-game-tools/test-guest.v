// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidhost as ah
import androidrun
import cachecli
import gamehost
import hosttest
import net.unix
import os
import sourcecommand
import time

fn line(mut connection unix.StreamConn) !map[string]ah.Value {
 mut bytes := []u8{}; mut buffer := []u8{len:1}
 for { count := connection.read(mut buffer)!; if count == 0 { return error('EOF') }; if buffer[0] == `\n` { break }; bytes << buffer[0] }
 return androidrun.load_json(bytes.bytestr())!.object()
}

fn mock_connection(mut listener unix.StreamListener, directory string, mode string) ! {
 mut connection := listener.accept()!; defer { connection.close() or {} }
 connection.write_string('{"QMP":{}}\n')!
 assert ah.field(line(mut connection)!,'execute').text() == 'qmp_capabilities'
 connection.write_string('{"return":{}}\n')!
 for {
  request := line(mut connection) or { return }
  command := ah.field(request,'execute').text()
  if command == 'input-send-event' {
   events := ah.field(ah.field(request,'arguments').object(),'events').items()
   assert events.len == 1
   key := events[0].object(); assert ah.field(key,'type').text() == 'key'
   data := ah.field(key,'data').object()
   name := ah.field(ah.field(data,'key').object(),'data').text()
   assert name in ['ret','up']
   down := ah.field(data,'down') == ah.Value(true)
   mut file := os.open_file(directory + '/keys','a')!; file.writeln(name + ':' + down.str())!; file.close()
   if mode == 'input-failure' { connection.write_string('{"error":{"desc":"controlled key failure"}}\n')!; return }
  } else if command == 'screendump' {
   if mode == 'screenshot-failure' { connection.write_string('{"error":{"desc":"controlled capture failure"}}\n')!; return }
   destination := ah.field(ah.field(request,'arguments').object(),'filename').text()
   mut pixels := 'P6\n2 1\n255\n'.bytes(); pixels << [u8(1),2,3,255,10,11]
   os.write_file_array(destination,pixels)!
  } else { return error('unexpected QMP command') }
  connection.write_string('{"event":"discarded"}\n{"return":{}}\n')!
 }
}

fn mock_listener(socket string, directory string, mode string) {
 mut listener := unix.listen_stream(socket) or { panic(err) }; defer { listener.close() or {} }
 for { mock_connection(mut listener,directory,mode) or { eprintln(err); return } }
}

fn mock_vm(directory string) ! {
 mode := os.read_file(directory + '/mode')!.trim_space()
 os.write_file(directory + '/child.pid',os.getpid().str())!
 if mode !in ['failure','interrupt','timeout'] { spawn mock_listener(directory + '/qmp.sock',directory,mode) }
 if mode == 'failure' { println('OPENGOTHIC-GONE'); flush_stdout() }
 else if mode == 'interrupt' || mode == 'timeout' { println('waiting controlled guest'); flush_stdout() }
 else {
  mut output := os.stdout()
  text := 'native serial drain\n'.repeat(70000) + 'Shader compilation took\nParsing object [MeshAndBsp\nunable to locate video file\nVINIX_VENUS_FENCE_FD_PASS\nVINIX_VENUS_GPU_FILL_PASS\nVENUS GPU: Virtio-GPU Venus\n'
  unsafe { output.write_full_buffer(text.str,usize(text.len))! }; output.flush()
 }
 for { println('0, 0, 60.0, 500'); flush_stdout(); time.sleep(500 * time.millisecond) }
}

fn prepare_fixture(argv []string, _ bool, _ voidptr) !sourcecommand.Output {
 name := argv[0].all_after_last('/')
 if name == 'compile-v-host' {
  assert argv[1] == 'winehost' && argv[3..] == ['--arch','arm64']
  os.write_file(argv[2],'generated-native-host')!
 } else {
  assert argv[0] == 'aarch64-linux-musl-gcc'
  assert argv[1..5] == ['-O2','-w','-D__vinix__','-I' + argv[5].all_before('/root/') + '/repo/build-aarch64-x11/sysroot/usr/include']
  assert argv[argv.len - 7..] == ['-lXtst','-lXdamage','-lX11','-lXext','-lxcb','-o',argv[5].all_before_last('/') + '/usr/bin/vinix-wine-host']
  os.write_file(argv.last(),'winehost')!
 }
 return sourcecommand.Output{}
}

fn options(root string, directory string, mode string) !gamehost.Options {
 repo := directory + '/repo'; build := directory + '/build'; kernel := directory + '/kernel'
 for relative in ['build-aarch64-x11/staging/usr/bin','build-aarch64-x11/staging/lib','build-aarch64-x11/staging/usr/lib','build-aarch64-x11/sysroot','build-aarch64-userland/staging/bin','build-aarch64-userland/staging/lib','scripts','boot-image'] { gamehost.mkdir(repo + '/' + relative)! }
 gamehost.mkdir(build + '/staging/usr/share/games/gothic2/_work/Data')!
 gamehost.mkdir(build + '/staging/usr/share/games/gothic2/_work/Video')!
 gamehost.mkdir(build + '/staging/opt/opengothic')!
 gamehost.mkdir(build + '/staging/usr/bin')!
 gamehost.mkdir(kernel + '/bin')!
 gamehost.mkdir(directory + '/venus/opt/venus/lib')!
 os.write_file(directory + '/mode',mode)!
 os.write_file(directory + '/desktop','desktop')!
 os.write_file(directory + '/override-engine','override')!
 os.write_file(directory + '/venus/opt/venus/lib/libvulkan_virtio.so','venus')!
 os.write_file(kernel + '/bin/vinix','frozen-kernel')!
 os.write_file(repo + '/build-aarch64-userland/staging/bin/busybox','busybox')!
 os.write_file(repo + '/build-aarch64-userland/staging/lib/libc.so','libc')!
 os.symlink('libc.so',repo + '/build-aarch64-userland/staging/lib/ld-musl.so')!
 os.write_file(build + '/staging/opt/opengothic/Gothic2Notr','engine')!
 os.write_file(build + '/staging/usr/bin/run-opengothic','set -eu\nfixture\n')!
 os.write_file(build + '/staging/usr/share/games/gothic2/_work/Video/InTrO.BiK','intro')!
 os.write_file(build + '/staging/usr/share/games/gothic2/_work/Video/keep.bik','keep')!
 script := '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' --mock-vm ' + hosttest.shell_quote(directory) + '\n'
 os.write_file(repo + '/scripts/run-aarch64.sh',script)!; os.chmod(repo + '/scripts/run-aarch64.sh',0o755)!
 return gamehost.Options{repo:repo,build:build,desktop:directory + '/desktop',kernel:kernel,work:directory,engine:directory + '/override-engine',venus_runtime:directory + '/venus',venus:mode == 'venus',seconds:2,warmup:0,timeout:if mode == 'timeout' { 5 } else { 30 }}
}

fn worker(root string, directory string, mode string) ! {
 settings := options(root,directory,mode)!
 tools := gamehost.Tools{root:root,command_hook:prepare_fixture}
 private := tools.prepare(settings)!
 assert os.readlink(private + '/bin/sh')! == 'busybox'
 assert os.readlink(private + '/lib/ld-musl.so')! == 'libc.so'
 assert os.readlink(private + '/usr/bin/vinix-opengothic')! == 'vinix-desktop'
 assert os.read_file(private + '/opt/opengothic/Gothic2Notr')! == 'override'
 assert !os.exists(private + '/usr/share/games/gothic2/_work/Video/InTrO.BiK')
 assert os.read_file(private + '/usr/share/games/gothic2/_work/Video/keep.bik')! == 'keep'
 assert os.stat(private + '/sbin/init')!.mode & 0o777 == 0o755
 if settings.venus { assert os.read_file(private + '/usr/bin/run-opengothic')!.contains('fps_sampling_period=500') }
 os.write_file(private + '/opt/opengothic/stale','stale')!
 tools.prepare(settings)!
 assert !os.exists(private + '/opt/opengothic/stale')
 assert os.read_file(private + '/.prepared')! == ''
 screenshot := gamehost.run_guest(settings,private)!
 assert screenshot == directory + '/gothic.png'
}

struct Interrupt { directory string signal int }
fn interrupt(pid int, pointer voidptr) ! {
 request := unsafe { &Interrupt(pointer) }
 deadline := time.sys_mono_now() + 10 * time.second
 for !os.exists(request.directory + '/child.pid') {
  if time.sys_mono_now() > deadline { return error('interrupt fixture child absent') }; time.sleep(10 * time.millisecond)
 }
 assert C.kill(pid,request.signal) == 0
}

fn state_cases() ! {
 second := u64(time.second)
 settings := gamehost.Options{seconds:2,warmup:1}
 mut state := gamehost.GameState{}
 state.ingest('Shader compilation took',second,settings)!
 assert state.advance(second,settings) == '' && state.menu == second
 assert state.advance(11 * second,settings) == ''
 assert state.advance(11 * second + 1,settings) == 'start'
 state.started = 12 * second
 state.ingest('Parsing object [MeshAndBsp',13 * second,settings)!
 assert state.advance(13 * second,settings) == '' && state.loading
 state.ingest('unable to locate video file',14 * second,settings)!
 state.advance(14 * second,settings)
 assert state.advance(17 * second,settings) == ''
 assert state.advance(17 * second + 1,settings) == 'capture'
 for marker in ['---crashlog(','KERNEL PANIC','OPENGOTHIC-GONE','VENUS-ABI-FAIL','VENUS-SMOKE-FAIL'] {
  mut failed := gamehost.GameState{transcript:marker}; assert failed.advance(second,settings) == 'failure'
 }
 original := '0, 0, 61.25, 123\r\n'
 for split in 0 .. original.len + 1 {
  values := [...gamehost.fps_samples('',original[..split])!,...gamehost.fps_samples(original[..split],original[split..])!]
  assert values == [61.25]
 }
 assert gamehost.fps_samples('0, 0, 55.0, 1\n','')!.len == 0
 assert gamehost.fps_samples('','x0, 0, 55.0, 1\n0, 0, x, 1\n0, 0, 55.0, x\n')!.len == 0
 gamehost.fps_samples('','0, 0, .., 1\n') or { return }
 return error('invalid FPS accepted')
}

fn main() {
 root := os.real_path(os.dir(@FILE) + '/../..')
 if os.args.len == 3 && os.args[1] == '--mock-vm' { mock_vm(os.args[2]) or { panic(err) }; return }
 guard := cachecli.own_commands(); defer { guard.close() }
 if os.args.len == 4 && os.args[1] == '--worker' {
  worker(root,os.args[2],os.args[3]) or { eprintln(err); exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }) }; return
 }
 if os.args.len != 2 { exit(2) }
 work := os.args[1]; gamehost.mkdir(work) or { panic(err) }
 state_cases() or { eprintln(err); exit(1) }
 for mode in ['complete','venus','failure','timeout','input-failure','screenshot-failure','interrupt-int','interrupt-term'] {
  directory := work + '/' + mode
  argv := [os.executable(),'--worker',directory,if mode.starts_with('interrupt') { 'interrupt' } else { mode }]
  mut result := sourcecommand.Output{}
  if mode.starts_with('interrupt') {
   request := Interrupt{directory:directory,signal:if mode.ends_with('int') { C.SIGINT } else { C.SIGTERM }}
   result = sourcecommand.capture_owned(argv,os.environ(),60,1024 * 1024,cachecli.cancelled,unsafe { nil },interrupt,&request,0) or { eprintln(err); exit(1) }
   assert result.status == if mode.ends_with('int') { 130 } else { 143 }
  } else { result = sourcecommand.capture(argv,os.environ(),60,1024 * 1024,cachecli.cancelled) or { eprintln(err); exit(1) } }
  os.write_file(directory + '/controller.log',result.stdout + result.stderr) or { panic(err) }
  assert !result.stdout.contains(': fn ') && !result.stderr.contains(': fn ')
  assert result.status == if mode in ['complete','venus'] { 0 } else if !mode.starts_with('interrupt') { 1 } else { result.status }, result.stderr
  child := (os.read_file(directory + '/child.pid') or { panic(err) }).int()
  assert C.kill(child,0) != 0 && C.errno == C.ESRCH
  if mode in ['complete','venus'] {
   assert os.file_size(directory + '/vinix.log') > 1200000
   assert os.read_file(directory + '/keys') or { panic(err) } == 'ret:true\nret:false\nup:true\nup:false\n'
   assert os.is_file(directory + '/gothic.png') && !os.exists(directory + '/gothic.ppm')
  }
  if mode == 'venus' { assert os.read_file(directory + '/performance.json') or { panic(err) }.contains('"median_fps": 60.0') }
 }
 os.write_file(work + '/passed','PASS\n') or { panic(err) }
 eprintln('NATIVE GOTHIC GUEST / prepare and rerun, strict timing/markers, every split FPS row, full real PTY/QMP capture and Venus report, four failures, SIGINT/SIGTERM and owner retirement: PASS')
}
