import os
import json2
fn main() {
 base:='build/android-maps/'
 os.write_file(base+'build-framework201.v',os.read_file(base+'build-framework198.v')!.replace('198','201'))!
 for baseline in [true,false] {
  name:='fixture-order201-'+if baseline {'baseline'} else {'fixed'}
  mut cfg:=json2.decode[map[string]json2.Any](os.read_file(base+'fixture-diagnostics190.json')!)!
  mut app:=cfg['applications']!.as_array()[0].as_map().clone()
  app['apk']=base+'order201-apk/bootstrap.apk'
  cfg['applications']=[json2.Any(app)]
  cfg['output']=base+name
  os.write_file(base+name+'.json',json2.encode(cfg,prettify:true)+'\n')!
 }
 os.write_file(base+'run-order201.v',"import os\nfn main(){\n baseline:=os.args.len>1 && os.args[1]=='baseline'\n fw:=if baseline {'198'} else {'201'}\n name:='fixture-order201-'+if baseline {'baseline'} else {'fixed'}\n base:='build/android-maps/'\n os.cp(base+'framework'+fw+'/api-impl.jar',base+'native/api-impl.jar')!\n os.cp(base+'libnative200.so',base+'native/libvinix-android-native.so')!\n os.cp(base+'launcher200',base+'native/popular-launcher')!\n r:=os.exec([base+'suite159',base+name+'.json']);print(r.output);assert r.exit_code==0,r.output\n}\n")!
}
