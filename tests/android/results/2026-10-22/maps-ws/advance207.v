import os
fn main(){
 b:='build/android-maps/'
 for src,dst in {'framework207/api-impl.jar':'framework207-initial.jar','framework207/framework-manifest.json':'framework207-initial-manifest.json','build-framework207.log':'build-framework207-initial.log'} {os.cp(b+src,b+dst)!}
 os.write_file(b+'framework207-initial-render_nodes.v',os.read_file('tests/native-android-tools/androidtools/framework_render_nodes.v')!.replace('new-instance v6, Landroid/graphics/Canvas;\ninvoke-direct {v6, v1}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V\nmove-object v2, v6','new-instance v2, Landroid/graphics/Canvas;\ninvoke-direct {v2, v1}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V'))!
 os.write_file(b+'fixture-render207-fixed2.json',os.read_file(b+'fixture-render207-fixed.json')!.replace('fixture-render207-fixed','fixture-render207-fixed2'))!
 os.write_file(b+'run-render207-fixed2.v',os.read_file(b+'run-render207.v')!.replace("'fixture-render207-'+if baseline {'baseline'} else {'fixed'}","'fixture-render207-'+if baseline {'baseline'} else {'fixed2'}"))!
}
