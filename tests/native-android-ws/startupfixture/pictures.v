// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_picture_probe(dir string) ! {
 mut check := '
new-instance v0, Landroid/graphics/Picture;
invoke-direct {v0}, Landroid/graphics/Picture;-><init>()V
invoke-virtual {v0}, Landroid/graphics/Picture;->getWidth()I
move-result v1
if-nez v1, :bad
const/4 v1, 4
invoke-virtual {v0, v1, v1}, Landroid/graphics/Picture;->beginRecording(II)Landroid/graphics/Canvas;
move-result-object v1
invoke-virtual {v0}, Landroid/graphics/Picture;->getWidth()I
move-result v2
const/4 v3, 4
if-ne v2, v3, :bad
invoke-virtual {v0}, Landroid/graphics/Picture;->getHeight()I
move-result v2
if-ne v2, v3, :bad
new-instance v2, Landroid/graphics/Paint;
invoke-direct {v2}, Landroid/graphics/Paint;-><init>()V
const v3, -0x10000
invoke-virtual {v2, v3}, Landroid/graphics/Paint;->setColor(I)V
new-instance v3, Landroid/graphics/Path;
invoke-direct {v3}, Landroid/graphics/Path;-><init>()V
move-object v4, v3
const/4 v5, 0
const/4 v6, 0
const/high16 v7, 0x40000000
const/high16 v8, 0x40000000
sget-object v9, Landroid/graphics/Path$Direction;->CW:Landroid/graphics/Path$Direction;
invoke-virtual/range {v4 .. v9}, Landroid/graphics/Path;->addRect(FFFFLandroid/graphics/Path$Direction;)V
invoke-virtual {v1}, Landroid/graphics/Canvas;->save()I
move-result v4
const/high16 v5, 0x3f800000
invoke-virtual {v1, v5, v5}, Landroid/graphics/Canvas;->translate(FF)V
invoke-virtual {v1, v3, v2}, Landroid/graphics/Canvas;->drawPath(Landroid/graphics/Path;Landroid/graphics/Paint;)V
invoke-virtual {v1, v4}, Landroid/graphics/Canvas;->restoreToCount(I)V
invoke-virtual {v1, v5, v5}, Landroid/graphics/Canvas;->translate(FF)V
invoke-virtual {v3}, Landroid/graphics/Path;->reset()V
const v3, -0xffff01
invoke-virtual {v2, v3}, Landroid/graphics/Paint;->setColor(I)V
new-instance v3, Landroid/graphics/Picture;
invoke-direct {v3, v0}, Landroid/graphics/Picture;-><init>(Landroid/graphics/Picture;)V
invoke-virtual {v0}, Landroid/graphics/Picture;->endRecording()V
const/4 v1, 4
invoke-virtual {v0, v1, v1}, Landroid/graphics/Picture;->beginRecording(II)Landroid/graphics/Canvas;
move-result-object v1
const v2, -0xff0100
invoke-virtual {v1, v2}, Landroid/graphics/Canvas;->drawColor(I)V
const/16 v1, 12
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v1, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v1
new-instance v2, Landroid/graphics/Canvas;
invoke-direct {v2, v1}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
const/high16 v4, 0x40000000
invoke-virtual {v2, v4, v4}, Landroid/graphics/Canvas;->translate(FF)V
invoke-virtual {v2, v4, v4}, Landroid/graphics/Canvas;->scale(FF)V
invoke-virtual {v2}, Landroid/graphics/Canvas;->save()I
move-result v4
invoke-virtual {v2, v3}, Landroid/graphics/Canvas;->drawPicture(Landroid/graphics/Picture;)V
invoke-virtual {v2}, Landroid/graphics/Canvas;->getSaveCount()I
move-result v5
add-int/lit8 v4, v4, 1
if-ne v4, v5, :bad
const/4 v4, 5
const/4 v5, 5
const v6, -0x10000
invoke-static {v1, v4, v5, v6}, Lorg/vinix/bootstrap/PictureProbe;->pixel(Landroid/graphics/Bitmap;III)V
const/4 v4, 3
const/4 v5, 3
const/4 v6, 0
invoke-static {v1, v4, v5, v6}, Lorg/vinix/bootstrap/PictureProbe;->pixel(Landroid/graphics/Bitmap;III)V
const/16 v4, 8
const/16 v5, 8
invoke-static {v1, v4, v5, v6}, Lorg/vinix/bootstrap/PictureProbe;->pixel(Landroid/graphics/Bitmap;III)V
invoke-virtual {v0, v2}, Landroid/graphics/Picture;->draw(Landroid/graphics/Canvas;)V
const/4 v4, 2
const/4 v5, 2
const v6, -0xff0100
invoke-static {v1, v4, v5, v6}, Lorg/vinix/bootstrap/PictureProbe;->pixel(Landroid/graphics/Bitmap;III)V
invoke-virtual {v3}, Landroid/graphics/Picture;->requiresHardwareAcceleration()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v1}, Landroid/graphics/Bitmap;->recycle()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-PICTURE-PASS dimensions commands mutable-arguments copy re-record scale restore auto-end"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Picture recording or playback state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 pixel := '
move-object v8, p0
const/4 v0, 1
new-array v1, v0, [I
const/4 v2, 0
const/4 v3, 1
move v4, p1
move v5, p2
const/4 v6, 1
const/4 v7, 1
move-object v0, v8
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
aget v0, v1, v2
if-eq v0, p3, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Picture playback pixel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void'
 os.write_file(dir + '/PictureProbe.smali', '.class public Lorg/vinix/bootstrap/PictureProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check()V', check) + method('private static pixel(Landroid/graphics/Bitmap;III)V', pixel))!
}
