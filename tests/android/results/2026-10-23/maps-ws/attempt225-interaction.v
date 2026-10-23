import os
import time

fn input(path string, action []string, settle string) {
 r:=os.exec(['build/android-run','input',...action,'--socket',path+'/qmp.sock','--settle',settle])
 assert r.exit_code==0,r.output
}
fn capture(path string, name string) {
 r:=os.exec(['build/android-run','screenshot','--socket',path+'/qmp.sock','--destination',path+'/'+name+'.png'])
 assert r.exit_code==0,r.output
 println('Captured '+name)
}
fn main() {
 path:=os.abs_path('build/android-maps/attempt225/google-maps')
 mut ready:=i64(0)
 for _ in 0..300 {
  log:=os.read_file(path+'/serial.log') or {''}
  assert !log.contains('APK-SUITE-EXIT id='),'Maps exited before interaction'
  if ready==0 && log.contains('ANDROID-WS-READY backend=vinix-native') {ready=time.now().unix_milli()}
  if ready>0 && time.now().unix_milli()-ready>30000 {break}
  time.sleep(time.second)
 }
 assert ready>0
 capture(path,'initial')
 input(path,['click','556','134'],'0.15')
 time.sleep(10*time.second)
 capture(path,'skip')
 time.sleep(15*time.second)
 capture(path,'skip-later')
}
