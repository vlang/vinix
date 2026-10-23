// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_glutils(smali string) ! {
 path := smali + '/android/opengl/GLUtils.smali'
 mut text := os.read_file(path)!
 signature := 'native_texSubImage2D(IIIILandroid/graphics/Bitmap;II)I'
 text = framework_replace_method(text, signature, '.method private static native ' + signature + '\n.end method')!
 for explicit in [false, true] {
  public_signature := 'texSubImage2D(IIIILandroid/graphics/Bitmap;' + if explicit { 'II)V' } else { ')V' }
  mut body := '.method public static ' + public_signature + '\n.locals 7\n'
  body += 'move v0, p0\nmove v1, p1\nmove v2, p2\nmove v3, p3\nmove-object v4, p4\n'
  body += if explicit { 'move v5, p5\nmove v6, p6\n' } else { 'const/4 v5, -1\nconst/4 v6, -1\n' }
  body += 'invoke-static/range {v0 .. v6}, Landroid/opengl/GLUtils;->' + signature + '\nmove-result v0\nif-eqz v0, :done\n'
  body += 'new-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "invalid Bitmap format"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:done\nreturn-void\n.end method'
  text = framework_replace_method(text, public_signature, body)!
 }
 os.write_file(path, text)!
}
