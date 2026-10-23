import os
fn main(){
 b:='build/android-maps/'
 r:=os.exec(['tar','-czf',b+'render207-initial-fixture-source.tar.gz','-C',b+'render207-apk','smali','res']);assert r.exit_code==0,r.output
 os.cp(b+'render207-apk/bootstrap.apk',b+'render207-initial.apk')!
 os.cp(b+'render207-apk-build.log',b+'render207-initial-apk-build.log')!
 for mode in ['baseline2','fixed3']{os.write_file(b+'fixture-render207-'+mode+'.json',os.read_file(b+'fixture-render207-baseline.json')!.replace('fixture-render207-baseline','fixture-render207-'+mode).replace('render207-apk','render207-final-apk'))!}
 mut run:=os.read_file(b+'run-render207.v')!.replace("{'baseline'} else {'fixed'}","{'baseline2'} else {'fixed3'}")
 os.write_file(b+'run-render207-final.v',run)!
 p:='tests/native-android-ws/startupfixture/render_nodes.v'
 mut s:=os.read_file(p)!.replace('invoke-virtual {v8, v3}, Landroid/graphics/Matrix;->equals(Ljava/lang/Object;)Z','invoke-static {v8, v3}, Lorg/vinix/bootstrap/RenderNodeProbe;->sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z').replace('invoke-virtual {v7, v3}, Landroid/graphics/Matrix;->equals(Ljava/lang/Object;)Z','invoke-static {v7, v3}, Lorg/vinix/bootstrap/RenderNodeProbe;->sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z')
 point:=" text += method('private static failure()V', render_node_failure_checks() + bad)"
 assert s.contains(point)
 s=s.replace(point,point+"\n text += method('private static sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z', 'const/16 v0, 9\\nnew-array v1, v0, [F\\nnew-array v2, v0, [F\\ninvoke-virtual {p0, v1}, Landroid/graphics/Matrix;->getValues([F)V\\ninvoke-virtual {p1, v2}, Landroid/graphics/Matrix;->getValues([F)V\\ninvoke-static {v1, v2}, Ljava/util/Arrays;->equals([F[F)Z\\nmove-result v0\\nreturn v0')")
 os.write_file(p,s)!
}
