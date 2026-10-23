import os
import androidtools
import crypto.sha256

fn main() {
 b:='build/android-maps/'
 dir:=b+'framework210'
 os.mkdir_all(dir)!
 smali:=dir+'/smali'
 os.cp_all(b+'framework208/smali',smali,true)!
 path:=smali+'/android/view/View.smali'
 mut s:=os.read_file(path)!
 s=s.replace('.method public onTouchEvent(Landroid/view/MotionEvent;)Z\n.locals 10', '.method public onTouchEvent(Landroid/view/MotionEvent;)Z\n.locals 10\nconst-string v0, "touch"\ninvoke-virtual {p0,p1,v0}, Landroid/view/View;->vinixTrace210(Landroid/view/MotionEvent;Ljava/lang/String;)V')
 at:=s.index('.method public performClick()Z') or {panic('performClick absent')}
 end:=s[at..].index('.end method') or {panic('end absent')}
 original:=s[at..at+end]
 modified:=original.replace('.registers 2', '.registers 4').replace('invoke-virtual {p0}', 'const/4 v0, 0\nconst-string v1, "click"\ninvoke-virtual {p0,v0,v1}, Landroid/view/View;->vinixTrace210(Landroid/view/MotionEvent;Ljava/lang/String;)V\ninvoke-virtual {p0}')
 assert modified!=original,original
 s=s.replace(original,modified)
 mut body:='.field private static vinixTraceCount210:I\n.method public vinixTrace210(Landroid/view/MotionEvent;Ljava/lang/String;)V\n.locals 5\nsget v0, Landroid/view/View;->vinixTraceCount210:I\nconst/16 v1, 200\nif-ge v0,v1,:done\nif-eqz p1,:count\ninvoke-virtual {p1}, Landroid/view/MotionEvent;->getActionMasked()I\nmove-result v1\nconst/4 v2,2\nif-eq v1,v2,:done\n:count\nadd-int/lit8 v0,v0,1\nsput v0,Landroid/view/View;->vinixTraceCount210:I\nnew-instance v0,Ljava/lang/StringBuilder;\ninvoke-direct {v0},Ljava/lang/StringBuilder;-><init>()V\nconst-string v1,"WS-TRACE210 "\ninvoke-virtual {v0,v1},Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\ninvoke-virtual {v0,p2},Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n'
 for pair in [[' id=','getId()I'],[' clickable=','isClickable()Z'],[' enabled=','isEnabled()Z'],[' pressed=','isPressed()Z'],[' alpha=','getAlpha()F']] {
  sig:=pair[1]
  body+='const-string v1,"'+pair[0]+'"\ninvoke-virtual {v0,v1},Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\ninvoke-virtual {p0},Landroid/view/View;->'+sig+'\nmove-result v1\ninvoke-virtual {v0,v1},Ljava/lang/StringBuilder;->append('+sig.all_after(')')+')Ljava/lang/StringBuilder;\n'
 }
 body+='invoke-virtual {p0},Ljava/lang/Object;->getClass()Ljava/lang/Class;\nmove-result-object v1\ninvoke-virtual {v1},Ljava/lang/Class;->getName()Ljava/lang/String;\nmove-result-object v1\ninvoke-virtual {v0,v1},Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\nif-eqz p1,:listener\ninvoke-virtual {p1},Landroid/view/MotionEvent;->getActionMasked()I\nmove-result v1\ninvoke-virtual {v0,v1},Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n:listener\niget-object v1,p0,Landroid/view/View;->on_click_listener:Landroid/view/View$OnClickListener;\nif-eqz v1,:print\ninvoke-virtual {v1},Ljava/lang/Object;->getClass()Ljava/lang/Class;\nmove-result-object v1\ninvoke-virtual {v1},Ljava/lang/Class;->getName()Ljava/lang/String;\nmove-result-object v1\ninvoke-virtual {v0,v1},Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n:print\ninvoke-virtual {v0},Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\nsget-object v1,Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v1,v0},Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n:done\nreturn-void\n.end method\n'
 os.write_file(path,s+'\n'+body)!
 group:=smali+'/android/view/ViewGroup.smali'
 text:=os.read_file(group)!.replace('iput-object v1, p0, Landroid/view/ViewGroup;->vinixTouchTarget:Landroid/view/View;\ngoto :finish','iput-object v1, p0, Landroid/view/ViewGroup;->vinixTouchTarget:Landroid/view/View;\nconst-string v3,"capture"\ninvoke-virtual {v1,p1,v3},Landroid/view/View;->vinixTrace210(Landroid/view/MotionEvent;Ljava/lang/String;)V\ngoto :finish')
 os.write_file(group,text)!
 androidtools.framework_assemble(smali,dir+'/classes.dex',os.abs_path('build/android-framework/tools'),'/opt/homebrew/opt/openjdk@25/bin/java')!
 os.cp(b+'framework208/api-impl.jar',dir+'/api-impl.jar')!
 r:=os.exec(['zip','-j',dir+'/api-impl.jar',dir+'/classes.dex'])
 assert r.exit_code==0,r.output
 println('FRAMEWORK210 '+sha256.sum(os.read_bytes(dir+'/api-impl.jar')!).hex())
 os.write_file(b+'attempt210.json',os.read_file(b+'attempt209.json')!.replace('attempt209','attempt210'))!
 os.write_file(b+'run210.v',os.read_file(b+'run209.v')!.replace('framework208','framework210').replace('attempt209','attempt210'))!
 os.write_file(b+'interact210.v',os.read_file(b+'interact209.v')!.replace('attempt209','attempt210'))!
 os.write_file(b+'stage-aux210.v',os.read_file(b+'stage-aux209.v')!.replace('attempt209','attempt210'))!
}
