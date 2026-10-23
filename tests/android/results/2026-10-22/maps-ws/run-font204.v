import os
fn main(){
 baseline:=os.args.len>1 && os.args[1]=='baseline'
 fw:=if baseline {'201'} else {'204'}
 name:='fixture-font204-'+if baseline {'baseline'} else {'fixed'}
 base:='build/android-maps/'
 os.cp(base+'framework'+fw+'/api-impl.jar',base+'native/api-impl.jar')!
 os.cp(base+'libnative'+if baseline {'200.so'} else {'204.so'},base+'native/libvinix-android-native.so')!
 os.cp(base+'launcher200',base+'native/popular-launcher')!
 r:=os.exec([base+'suite159',base+name+'.json']);print(r.output);assert r.exit_code==0,r.output
}
