// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_egl_error_names(smali string) ! {
 path := smali + '/android/opengl/GLUtils.smali'
 mut text := os.read_file(path)!
 if text.contains(' getEGLErrorString(') { return error('EGL error formatter already installed') }
 names := ['EGL_SUCCESS', 'EGL_NOT_INITIALIZED', 'EGL_BAD_ACCESS', 'EGL_BAD_ALLOC',
  'EGL_BAD_ATTRIBUTE', 'EGL_BAD_CONFIG', 'EGL_BAD_CONTEXT', 'EGL_BAD_CURRENT_SURFACE',
  'EGL_BAD_DISPLAY', 'EGL_BAD_MATCH', 'EGL_BAD_NATIVE_PIXMAP', 'EGL_BAD_NATIVE_WINDOW',
  'EGL_BAD_PARAMETER', 'EGL_BAD_SURFACE', 'EGL_CONTEXT_LOST']
 mut method := r'
.method public static getEGLErrorString(I)Ljava/lang/String;
.locals 2
packed-switch p0, :codes
invoke-static {p0}, Ljava/lang/Integer;->toHexString(I)Ljava/lang/String;
move-result-object v0
const-string v1, "0x"
invoke-virtual {v1, v0}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
return-object v0
'
 for index, name in names {
  method += ':e${index}\nconst-string v0, "${name}"\nreturn-object v0\n'
 }
 method += ':codes\n.packed-switch 0x3000\n'
 for index in 0 .. names.len { method += ':e${index}\n' }
 method += '.end packed-switch\n.end method\n'
 text += method
 os.write_file(path, text)!
}

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
