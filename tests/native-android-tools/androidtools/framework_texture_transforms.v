// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// A TextureView's content transform is independent of View geometry. Retain a
// private copy even before a surface is available, matching Android's Matrix
// copy/reset contract. The current backend reports its texture unavailable;
// this property must not transform the background or manufacture a surface.
fn framework_texture_transforms(smali string) ! {
 path := smali + '/android/view/TextureView.smali'
 mut text := os.read_file(path)!
 text += '\n.field private vinixContentTransform:Landroid/graphics/Matrix;\n'
 text = framework_replace_method(text, 'setTransform(Landroid/graphics/Matrix;)V',
  '.method public setTransform(Landroid/graphics/Matrix;)V\n.locals 1\n' +
  'iget-object v0, p0, Landroid/view/TextureView;->vinixContentTransform:Landroid/graphics/Matrix;\n' +
  'if-nez v0, :copy\nnew-instance v0, Landroid/graphics/Matrix;\ninvoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V\n' +
  'iput-object v0, p0, Landroid/view/TextureView;->vinixContentTransform:Landroid/graphics/Matrix;\n' +
  ':copy\ninvoke-virtual {v0, p1}, Landroid/graphics/Matrix;->set(Landroid/graphics/Matrix;)V\n' +
  'invoke-virtual {p0}, Landroid/view/View;->invalidate()V\nreturn-void\n.end method')!
 text = framework_replace_method(text, 'getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;',
  '.method public getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;\n.locals 2\n' +
  'move-object v0, p1\nif-nez v0, :copy\nnew-instance v0, Landroid/graphics/Matrix;\ninvoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V\n' +
  ':copy\niget-object v1, p0, Landroid/view/TextureView;->vinixContentTransform:Landroid/graphics/Matrix;\n' +
  'invoke-virtual {v0, v1}, Landroid/graphics/Matrix;->set(Landroid/graphics/Matrix;)V\nreturn-object v0\n.end method')!
 os.write_file(path, text)!
}
