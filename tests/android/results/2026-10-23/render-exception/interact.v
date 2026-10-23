import os
import time
import net.unix
import json2

fn reply(mut stream unix.StreamConn) ! {
 mut line := ''
 for {
  mut byte := [u8(0)]!
  count := stream.read(mut byte)!
  assert count == 1, 'QMP disconnected'
  if byte[0] == 10 {
   result := json2.decode[map[string]json2.Any](line)!
   assert 'error' !in result, line
   if 'return' in result { return }
   line = ''
  } else { line += byte[0].ascii_str() }
 }
}

fn send(socket string, arguments string) ! {
 mut stream := unix.connect_stream(socket)!
 defer { stream.close() or {} }
 stream.set_read_timeout(10 * time.second)
 stream.write_string('{"execute":"qmp_capabilities"}\n')!
 reply(mut stream)!
 stream.write_string('{"execute":"input-send-event","arguments":' + arguments + '}\n')!
 reply(mut stream)!
}

fn main() {
 assert os.args.len == 2 && os.args[1] in ['baseline', 'fixed']
 path := os.abs_path('build/android-maps/render230/run-' + os.args[1] + '/render-exception')
 mut positioned := false
 for _ in 0 .. 3000 {
  log := os.read_file(path + '/serial.log') or { '' }
  assert !log.contains('APK-SUITE-EXIT id='), 'Fixture exited before queued input'
  if !positioned && log.contains('RENDER-EXCEPTION-POSITION-WINDOW') {
   send(path + '/qmp.sock', '{"events":[{"type":"abs","data":{"axis":"x","value":9610}},{"type":"abs","data":{"axis":"y","value":12816}}]}')!
   positioned = true
   println('POINTER-POSITIONED at=' + time.now().str())
  }
  if log.contains('RENDER-EXCEPTION-DRAW-ENTER') {
   assert positioned
   println('DRAW-ENTER-OBSERVED at=' + time.now().str())
   send(path + '/qmp.sock', '{"events":[{"type":"btn","data":{"down":true,"button":"left"}}]}')!
   println('BUTTON-DOWN-QUEUED at=' + time.now().str())
   return
  }
  time.sleep(100 * time.millisecond)
 }
 panic('Draw callback marker timed out')
}
