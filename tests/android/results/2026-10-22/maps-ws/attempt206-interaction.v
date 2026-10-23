import os
import time
import json2
import qmpclient

fn input(path string, action []string, settle string) {
 r:=os.exec(['build/android-run','input',...action,'--socket',path+'/qmp.sock','--settle',settle])
 assert r.exit_code==0,r.output
}
fn capture(path string, name string) {
 r:=os.exec(['build/android-run','screenshot','--socket',path+'/qmp.sock','--destination',path+'/'+name+'.png'])
 assert r.exit_code==0,r.output
 println('Captured '+name)
}
fn doubletap(path string) ! {
 mut q:=qmpclient.connect(path+'/qmp.sock')!
 defer{q.close()}
 mut axes:=[]json2.Any{}
 for axis,value in {'x':360*32767/1023,'y':300*32767/767} {
  axes<<json2.Any({'type':json2.Any('abs'),'data':json2.Any({'axis':json2.Any(axis),'value':json2.Any(value)})})
 }
 q.command('input-send-event',{'events':json2.Any(axes)})!
 time.sleep(100*time.millisecond)
 for _ in 0..2 {
  for down in [true,false] {
   q.command('input-send-event',{'events':json2.Any([json2.Any({'type':json2.Any('btn'),'data':json2.Any({'button':json2.Any('left'),'down':json2.Any(down)})})])})!
   time.sleep(70*time.millisecond)
  }
 }
}
fn main() {
 path:=os.abs_path('build/android-maps/attempt206/google-maps')
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
 input(path,['click','556','134'],'15')
 capture(path,'skip')
 input(path,['drag','430','350','240','350'],'5')
 capture(path,'pan')
 doubletap(path)!
 time.sleep(6*time.second)
 capture(path,'zoom')
 input(path,['click','300','138'],'1')
 input(path,['click','320','138'],'1')
 input(path,['type','London'],'3')
 capture(path,'search-typed')
 input(path,['type','\n'],'20')
 capture(path,'search')
 time.sleep(30*time.second)
 capture(path,'search-later')
 input(path,['drag','360','541','360','220'],'8')
 capture(path,'sheet')
}
