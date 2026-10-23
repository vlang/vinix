import os
import androidtools
import crypto.sha256
fn main(){
 b:='build/android-maps/'
 dir:=b+'framework211'
 os.mkdir_all(dir)!
 smali:=dir+'/smali'
 os.cp_all(b+'framework210/smali',smali,true)!
 path:=smali+'/android/view/View.smali'
 mut s:=os.read_file(path)!
 s=s.replace('invoke-virtual {p0}, Landroid/view/View;->callOnClick()Z','invoke-direct {p0}, Landroid/view/View;->vinixTrace211()V\ninvoke-virtual {p0}, Landroid/view/View;->callOnClick()Z')
 s+='
.method private vinixTrace211()V
.locals 5
:start
iget-object v0,p0,Landroid/view/View;->on_click_listener:Landroid/view/View$OnClickListener;
if-eqz v0,:done
invoke-virtual {v0},Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1},Ljava/lang/Class;->getName()Ljava/lang/String;
move-result-object v2
const-string v3,"bhaf"
invoke-virtual {v3,v2},Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2,:done
const-string v2,"a"
invoke-virtual {v1,v2},Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v1
const/4 v2,1
invoke-virtual {v1,v2},Ljava/lang/reflect/Field;->setAccessible(Z)V
invoke-virtual {v1,v0},Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
sget-object v1,Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v2,"WS-TRACE211 actual click map:"
invoke-virtual {v1,v2},Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v1,v0},Ljava/io/PrintStream;->println(Ljava/lang/Object;)V
:end
.catch Ljava/lang/Exception; {:start .. :end} :failed
goto :done
:failed
move-exception v0
invoke-virtual {v0},Ljava/lang/Throwable;->printStackTrace()V
:done
return-void
.end method
'
 os.write_file(path,s)!
 androidtools.framework_assemble(smali,dir+'/classes.dex',os.abs_path('build/android-framework/tools'),'/opt/homebrew/opt/openjdk@25/bin/java')!
 os.cp(b+'framework210/api-impl.jar',dir+'/api-impl.jar')!
 r:=os.exec(['zip','-j',dir+'/api-impl.jar',dir+'/classes.dex']);assert r.exit_code==0,r.output
 println('FRAMEWORK211 '+sha256.sum(os.read_bytes(dir+'/api-impl.jar')!).hex())
 os.write_file(b+'attempt211.json',os.read_file(b+'attempt210.json')!.replace('attempt210','attempt211').replace('180','120'))!
 os.write_file(b+'run211.v',os.read_file(b+'run210.v')!.replace('framework210','framework211').replace('attempt210','attempt211'))!
 os.write_file(b+'interact211.v',os.read_file(b+'interact210.v')!.replace('attempt210','attempt211'))!
 os.write_file(b+'stage-aux211.v',os.read_file(b+'stage-aux210.v')!.replace('attempt210','attempt211'))!
}
