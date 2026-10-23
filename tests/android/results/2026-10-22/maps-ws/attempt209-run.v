import os
fn main() {
 base:='build/android-maps/'
 os.cp(base+'libnative209.so',base+'native/libvinix-android-native.so')!
 os.cp(base+'framework208/api-impl.jar',base+'native/api-impl.jar')!
 os.cp(base+'launcher200',base+'native/popular-launcher')!
 r:=os.exec([base+'suite159',base+'attempt209.json'])
 print(r.output)
 assert r.exit_code==0,r.output
}
