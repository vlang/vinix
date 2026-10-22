// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_image_filters(smali string) ! {
 path := smali + '/android/widget/ImageView.smali'
 mut text := os.read_file(path)!
 text = framework_replace_method(text, 'setColorFilter(Landroid/graphics/ColorFilter;)V', image_filter_method(
  'setColorFilter(Landroid/graphics/ColorFilter;)V', '
iput-object p1, p0, Landroid/widget/ImageView;->colorFilter:Landroid/graphics/ColorFilter;
iget-object v0, p0, Landroid/widget/ImageView;->drawable:Landroid/graphics/drawable/Drawable;
if-eqz v0, :invalidate
invoke-virtual {v0}, Landroid/graphics/drawable/Drawable;->mutate()Landroid/graphics/drawable/Drawable;
move-result-object v0
iput-object v0, p0, Landroid/widget/ImageView;->drawable:Landroid/graphics/drawable/Drawable;
invoke-virtual {v0, p1}, Landroid/graphics/drawable/Drawable;->setColorFilter(Landroid/graphics/ColorFilter;)V
:invalidate
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
return-void'))!
 text = framework_replace_method(text, 'setColorFilter(I)V', image_filter_method('setColorFilter(I)V', '
sget-object v0, Landroid/graphics/PorterDuff$Mode;->SRC_ATOP:Landroid/graphics/PorterDuff$Mode;
invoke-virtual {p0, p1, v0}, Landroid/widget/ImageView;->setColorFilter(ILandroid/graphics/PorterDuff$Mode;)V
return-void'))!
 text = framework_replace_method(text, 'setColorFilter(ILandroid/graphics/PorterDuff$Mode;)V', image_filter_method(
  'setColorFilter(ILandroid/graphics/PorterDuff$Mode;)V', '
new-instance v0, Landroid/graphics/PorterDuffColorFilter;
invoke-direct {v0, p1, p2}, Landroid/graphics/PorterDuffColorFilter;-><init>(ILandroid/graphics/PorterDuff$Mode;)V
invoke-virtual {p0, v0}, Landroid/widget/ImageView;->setColorFilter(Landroid/graphics/ColorFilter;)V
return-void'))!
 text += image_filter_method('getColorFilter()Landroid/graphics/ColorFilter;',
  'iget-object v0, p0, Landroid/widget/ImageView;->colorFilter:Landroid/graphics/ColorFilter;\nreturn-object v0')
 text += image_filter_method('clearColorFilter()V',
  'const/4 v0, 0\ninvoke-virtual {p0, v0}, Landroid/widget/ImageView;->setColorFilter(Landroid/graphics/ColorFilter;)V\nreturn-void')
 os.write_file(path, text)!
 drawable := smali + '/android/graphics/drawable/Drawable.smali'
 os.write_file(drawable, framework_replace_method(os.read_file(drawable)!, 'clearColorFilter()V',
  image_filter_method('clearColorFilter()V',
   'const/4 v0, 0\ninvoke-virtual {p0, v0}, Landroid/graphics/drawable/Drawable;->setColorFilter(Landroid/graphics/ColorFilter;)V\nreturn-void'))!)!
}

fn image_filter_method(signature string, body string) string {
 return '.method public ' + signature + '\n.locals 1\n' + body + '\n.end method\n'
}
