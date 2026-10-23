import os
import json2
fn main(){
 b:='build/android-maps/'
 mut cfg:=json2.decode[map[string]json2.Any](os.read_file(b+'attempt200.json')!)!
 cfg['output']=b+'attempt203'
 os.write_file(b+'attempt203.json',json2.encode(cfg,prettify:true)+'\n')!
 os.write_file(b+'run203.v',os.read_file(b+'run200.v')!.replace('framework198','framework201').replace('attempt200','attempt203'))!
 mut interact:=os.read_file(b+'interact200.v')!.replace('attempt200','attempt203')
 interact=interact.replace("capture(path,'initial')","capture(path,'initial')\n input(path,['click','556','134'],'15')\n capture(path,'skip')")
 os.write_file(b+'interact203.v',interact)!
}
