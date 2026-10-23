import os
import crypto.sha256
import json2
fn main(){
 base:='build/android-maps/attempt213/'
 mut hashes:=map[string]string{}
 for file in ['usr/bin/run-android','usr/bin/run-android-calculator','usr/bin/vinix-desktop','opt/android-test/native-guest']{hashes[file]=sha256.sum(os.read_bytes(base+'module/'+file)!).hex()}
 assert hashes['usr/bin/run-android-calculator']==sha256.sum(os.read_bytes('build/android-maps/launcher200')!).hex()
 os.write_file(base+'launcher-runtime-sha256.json',json2.encode(hashes,prettify:true)+'\n')!
 println('Verified staged launcher against launcher200; retained four host/guest entry hashes')
}
