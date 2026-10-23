import os
fn main(){
 baseline:=os.args.len>1 && os.args[1]=='baseline'
 fw:=if baseline {'205'} else {'206'}
 name:='fixture-drawing206-'+if baseline {'baseline'} else {'fixed'}
 base:='build/android-maps/'
 os.cp(base+'framework'+fw+'/api-impl.jar',base+'native/api-impl.jar')!
 os.cp(base+'libnative204.so',base+'native/libvinix-android-native.so')!
 os.cp(base+'launcher200',base+'native/popular-launcher')!
 r:=os.exec([base+'suite159',base+name+'.json']);print(r.output);assert r.exit_code==0,r.output
}
