import os
import json2
fn main(){
 p:='build/android-maps/attempt213'
 f:=json2.decode[[]json2.Any](os.read_file(p+'/results.json')!)!
 for item in f { row:=item.as_map(); for k,v in row { if k in ['id','verdict','error','failure','failure_reason','status'] {println(k+': '+v.str())} } }
 assert !os.is_file(p+'/google-maps/serial.log')
 os.cp(p+'/results.json','build/android-maps/attempt213-stage-failure.json')!
 os.rmdir_all(p)!
}
