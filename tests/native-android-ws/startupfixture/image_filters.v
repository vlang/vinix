// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_image_filter_probe(dir string) ! {
 os.write_file(dir + '/FilterDrawable.smali', '.class public Lorg/vinix/bootstrap/FilterDrawable;\n.super Landroid/graphics/drawable/ColorDrawable;\n' +
  '.field public seen:Landroid/graphics/ColorFilter;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/graphics/drawable/ColorDrawable;-><init>()V\nreturn-void') +
  method('public setColorFilter(Landroid/graphics/ColorFilter;)V', 'iput-object p1, p0, Lorg/vinix/bootstrap/FilterDrawable;->seen:Landroid/graphics/ColorFilter;\nreturn-void'))!
 os.write_file(dir + '/ImageFilterProbe.smali', '.class public Lorg/vinix/bootstrap/ImageFilterProbe;\n.super Ljava/lang/Object;\n' + method('public static check(Landroid/content/Context;)V', '
new-instance v0, Landroid/widget/ImageView;
invoke-direct {v0, p0}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/graphics/PorterDuffColorFilter;
const v2, 0xff00ff00
sget-object v3, Landroid/graphics/PorterDuff$Mode;->SRC_IN:Landroid/graphics/PorterDuff$Mode;
invoke-direct {v1, v2, v3}, Landroid/graphics/PorterDuffColorFilter;-><init>(ILandroid/graphics/PorterDuff$Mode;)V
invoke-virtual {v0, v1}, Landroid/widget/ImageView;->setColorFilter(Landroid/graphics/ColorFilter;)V
invoke-virtual {v0}, Landroid/widget/ImageView;->getColorFilter()Landroid/graphics/ColorFilter;
move-result-object v2
if-ne v1, v2, :bad
new-instance v2, Lorg/vinix/bootstrap/FilterDrawable;
invoke-direct {v2}, Lorg/vinix/bootstrap/FilterDrawable;-><init>()V
invoke-virtual {v0, v2}, Landroid/widget/ImageView;->setImageDrawable(Landroid/graphics/drawable/Drawable;)V
iget-object v3, v2, Lorg/vinix/bootstrap/FilterDrawable;->seen:Landroid/graphics/ColorFilter;
if-ne v1, v3, :bad
invoke-virtual {v0}, Landroid/widget/ImageView;->clearColorFilter()V
invoke-virtual {v0}, Landroid/widget/ImageView;->getColorFilter()Landroid/graphics/ColorFilter;
move-result-object v3
if-nez v3, :bad
iget-object v3, v2, Lorg/vinix/bootstrap/FilterDrawable;->seen:Landroid/graphics/ColorFilter;
if-nez v3, :bad
invoke-virtual {v0, v1}, Landroid/widget/ImageView;->setColorFilter(Landroid/graphics/ColorFilter;)V
iget-object v3, v2, Lorg/vinix/bootstrap/FilterDrawable;->seen:Landroid/graphics/ColorFilter;
if-ne v1, v3, :bad
invoke-virtual {v2}, Landroid/graphics/drawable/Drawable;->clearColorFilter()V
iget-object v3, v2, Lorg/vinix/bootstrap/FilterDrawable;->seen:Landroid/graphics/ColorFilter;
if-nez v3, :bad
const v1, 0xff0000ff
invoke-virtual {v0, v1}, Landroid/widget/ImageView;->setColorFilter(I)V
invoke-virtual {v0}, Landroid/widget/ImageView;->getColorFilter()Landroid/graphics/ColorFilter;
move-result-object v1
if-eqz v1, :bad
iget-object v3, v2, Lorg/vinix/bootstrap/FilterDrawable;->seen:Landroid/graphics/ColorFilter;
if-ne v1, v3, :bad
invoke-virtual {v0}, Landroid/widget/ImageView;->clearColorFilter()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-IMAGE-FILTER-PASS retained-state drawable-replacement dispatch clear integer-overload"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ImageView color-filter state and forwarding"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
