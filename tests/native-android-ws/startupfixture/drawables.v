// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_drawable_probe(dir string) ! {
 os.write_file(dir + '/DrawableProbe.smali', '.class public Lorg/vinix/bootstrap/DrawableProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', '
new-instance v0, Landroid/graphics/drawable/GradientDrawable;
invoke-direct {v0}, Landroid/graphics/drawable/GradientDrawable;-><init>()V
const/4 v1, 2
new-array v2, v1, [[I
new-array v3, v1, [I
const/4 v4, 1
new-array v5, v4, [I
const v6, 0x10100a7
const/4 v7, 0
aput v6, v5, v7
aput-object v5, v2, v7
new-array v6, v7, [I
aput-object v6, v2, v4
const v8, -0x10000
aput v8, v3, v7
const v8, -0xff0100
aput v8, v3, v4
new-instance v9, Landroid/content/res/ColorStateList;
invoke-direct {v9, v2, v3}, Landroid/content/res/ColorStateList;-><init>([[I[I)V
invoke-virtual {v0, v9}, Landroid/graphics/drawable/GradientDrawable;->setColor(Landroid/content/res/ColorStateList;)V
invoke-virtual {v0}, Landroid/graphics/drawable/GradientDrawable;->getColor()Landroid/content/res/ColorStateList;
move-result-object v1
if-ne v1, v9, :bad
invoke-virtual {v0}, Landroid/graphics/drawable/GradientDrawable;->isStateful()Z
move-result v1
if-eqz v1, :bad
const v1, -0xff0100
invoke-static {v0, v1}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v0, v5}, Landroid/graphics/drawable/GradientDrawable;->setState([I)Z
move-result v1
if-eqz v1, :bad
const v1, -0x10000
invoke-static {v0, v1}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v0}, Landroid/graphics/drawable/GradientDrawable;->getConstantState()Landroid/graphics/drawable/Drawable$ConstantState;
move-result-object v1
invoke-virtual {v1}, Landroid/graphics/drawable/Drawable$ConstantState;->newDrawable()Landroid/graphics/drawable/Drawable;
move-result-object v2
check-cast v2, Landroid/graphics/drawable/GradientDrawable;
invoke-virtual {v2}, Landroid/graphics/drawable/GradientDrawable;->mutate()Landroid/graphics/drawable/Drawable;
invoke-virtual {v2, v5}, Landroid/graphics/drawable/GradientDrawable;->setState([I)Z
const v1, -0x10000
invoke-static {v2, v1}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v2, v7}, Landroid/graphics/drawable/GradientDrawable;->setColor(I)V
invoke-virtual {v2}, Landroid/graphics/drawable/GradientDrawable;->isStateful()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/graphics/drawable/GradientDrawable;->isStateful()Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/graphics/drawable/GradientDrawable;->setColor(Landroid/content/res/ColorStateList;)V
invoke-virtual {v0}, Landroid/graphics/drawable/GradientDrawable;->getColor()Landroid/content/res/ColorStateList;
move-result-object v1
if-nez v1, :bad
invoke-static {v0, v7}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v0, v9}, Landroid/graphics/drawable/GradientDrawable;->setColor(Landroid/content/res/ColorStateList;)V
invoke-virtual {v0, v3}, Landroid/graphics/drawable/GradientDrawable;->setColors([I)V
invoke-virtual {v0}, Landroid/graphics/drawable/GradientDrawable;->getColor()Landroid/content/res/ColorStateList;
move-result-object v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/graphics/drawable/GradientDrawable;->isStateful()Z
move-result v1
if-nez v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-DRAWABLE-PASS stateful-fill rendered-pixels constant-state mutate null gradient-reset"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "gradient stateful colors"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static pixel(Landroid/graphics/drawable/GradientDrawable;I)V', '
const/4 v0, 4
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v1
new-instance v2, Landroid/graphics/Canvas;
invoke-direct {v2, v1}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
const/4 v3, 0
invoke-virtual {p0, v3, v3, v0, v0}, Landroid/graphics/drawable/GradientDrawable;->setBounds(IIII)V
invoke-virtual {p0, v2}, Landroid/graphics/drawable/GradientDrawable;->draw(Landroid/graphics/Canvas;)V
move-object v8, v1
move-object v0, v1
const/4 v2, 1
new-array v1, v2, [I
const/4 v2, 0
const/4 v3, 1
const/4 v4, 2
const/4 v5, 2
const/4 v6, 1
const/4 v7, 1
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
aget v0, v1, v2
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
if-eq v0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "gradient rendered pixel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void'))!
}
