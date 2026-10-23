import os
import time
fn main() {
	path:=os.abs_path('build/android-maps/attempt163/google-maps')
	mut ready:=i64(0)
	for _ in 0..300 {
		log:=os.read_file(path+'/serial.log') or {''}
		assert !log.contains('APK-SUITE-EXIT id='),'Maps exited before interaction'
		if ready==0 && log.contains('ANDROID-WS-READY backend=vinix-native') {ready=time.now().unix_milli()}
		if ready>0 && time.now().unix_milli()-ready>40000 {break}
		time.sleep(time.second)
	}
	assert ready>0
	for name, action in {'initial':[]string{},'pan':['drag','430','350','240','350'],'zoom':['click','360','300']} {
		if action.len>0 {
			r:=os.exec(['build/android-run','input',...action,'--socket',path+'/qmp.sock','--settle',if name=='zoom' {'0.04'}else{'6'}])
			assert r.exit_code==0,r.output
			if name=='zoom' {
				s:=os.exec(['build/android-run','input',...action,'--socket',path+'/qmp.sock','--settle','6'])
				assert s.exit_code==0,s.output
			}
		}
		r:=os.exec(['build/android-run','screenshot','--socket',path+'/qmp.sock','--destination',path+'/'+name+'.png'])
		assert r.exit_code==0,r.output
		println('Captured '+name)
	}
	r:=os.exec(['/Users/alex/code/v/v','-nocache','-cc','cc','run','build/android-maps/search134.v','attempt163'])
	println(r.output)
	assert r.exit_code==0
}
