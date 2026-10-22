// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import math
import os

fn fit_float(register string, number string) string {
 return 'const ${register}, 0x${math.f32_bits(number.f32()):08x}\n'
}

fn install_matrix_fit_probe(dir string) ! {
 mut check := ''
 // Source; destination; alignment; expected scale/translation; success.
 // Expected values are explicit, independent of the native fit calculation.
 for row in [
  '-2,3,8,8;10,20,50,80;FILL;4,12,18,-16;1',
  '-2,3,8,8;10,20,50,80;START;4,4,18,8;1',
  '-2,3,8,8;10,20,50,80;CENTER;4,4,18,28;1',
  '-2,3,8,8;10,20,50,80;END;4,4,18,48;1',
  '-2,3,3,13;10,20,70,60;FILL;12,4,34,8;1',
  '-2,3,3,13;10,20,70,60;START;4,4,18,8;1',
  '-2,3,3,13;10,20,70,60;CENTER;4,4,38,8;1',
  '-2,3,3,13;10,20,70,60;END;4,4,58,8;1',
  '2,4,10,8;-7,-9,5,-1;CENTER;1.5,1.5,-10,-14;1',
  '3,4,3,8;10,20,50,80;FILL;1,1,0,0;0',
  '3,8,7,4;10,20,50,80;END;1,1,0,0;0',
  '3,4,7,8;10,20,10,80;CENTER;0,0,0,0;1',
  '3,4,7,8;50,20,10,80;START;0,0,0,0;1',
  '3,4,3,8;10,20,10,80;FILL;1,1,0,0;0',
 ] {
  parts := row.split(';')
  check += 'new-instance v0, Landroid/graphics/Matrix;\ninvoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V\n'
  // A preexisting nonidentity transform must be replaced in every case.
  check += fit_float('v1', '7') + fit_float('v2', '11') + 'invoke-virtual {v0, v1, v2}, Landroid/graphics/Matrix;->setTranslate(FF)V\n'
  for i in 0 .. 2 {
   check += 'new-instance v${i + 1}, Landroid/graphics/RectF;\n'
   for j, number in parts[i].split(',') { check += fit_float('v${j + 3}', number) }
   check += 'invoke-direct {v${i + 1}, v3, v4, v5, v6}, Landroid/graphics/RectF;-><init>(FFFF)V\n'
  }
  check += 'sget-object v3, Landroid/graphics/Matrix$ScaleToFit;->${parts[2]}:Landroid/graphics/Matrix$ScaleToFit;\n' +
   'invoke-virtual {v0, v1, v2, v3}, Landroid/graphics/Matrix;->setRectToRect(Landroid/graphics/RectF;Landroid/graphics/RectF;Landroid/graphics/Matrix$ScaleToFit;)Z\n' +
   'move-result v3\nconst/4 v4, ${parts[4]}\nif-ne v3, v4, :bad\n'
  // Inputs must remain unchanged, including empty and inverted rectangles.
  for i in 0 .. 2 {
   for j, name in ['left', 'top', 'right', 'bottom'] {
    check += 'iget v3, v${i + 1}, Landroid/graphics/RectF;->${name}:F\n' + fit_float('v4', parts[i].split(',')[j]) +
     'cmpl-float v3, v3, v4\nif-nez v3, :bad\n'
   }
  }
  expected := parts[3].split(',')
  check += 'const/16 v1, 9\nnew-array v1, v1, [F\n'
  for i, number in [expected[0], '0', expected[2], '0', expected[1], expected[3], '0', '0', '1'] {
   check += fit_float('v2', number) + 'const/16 v3, ${i}\naput v2, v1, v3\n'
  }
  check += 'invoke-static {v0, v1}, Lorg/vinix/bootstrap/MatrixFitProbe;->values(Landroid/graphics/Matrix;[F)V\n'
 }
 check += '
invoke-static {}, Lorg/vinix/bootstrap/MatrixFitProbe;->aliasAndNull()V
invoke-static {}, Lorg/vinix/bootstrap/MatrixFitProbe;->pixels()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-MATRIX-FIT-PASS fill start center end both-axes fractional empty-source empty-destination reset unchanged-input alias null canvas-pixels"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Matrix rectangle fit return value or input mutation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 mut nulls := '
new-instance v0, Landroid/graphics/Matrix;
invoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V
new-instance v1, Landroid/graphics/RectF;
const/high16 v2, 0x3f800000
const/high16 v3, 0x40000000
invoke-direct {v1, v2, v2, v3, v3}, Landroid/graphics/RectF;-><init>(FFFF)V
sget-object v2, Landroid/graphics/Matrix$ScaleToFit;->CENTER:Landroid/graphics/Matrix$ScaleToFit;
invoke-virtual {v0, v1, v1, v2}, Landroid/graphics/Matrix;->setRectToRect(Landroid/graphics/RectF;Landroid/graphics/RectF;Landroid/graphics/Matrix$ScaleToFit;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v0}, Landroid/graphics/Matrix;->isIdentity()Z
move-result v3
if-eqz v3, :bad
const/4 v3, 0
'
 for i, args in ['v0, v3, v1, v2', 'v0, v1, v3, v2', 'v0, v1, v1, v3'] {
  nulls += ':try_${i}\ninvoke-virtual {${args}}, Landroid/graphics/Matrix;->setRectToRect(Landroid/graphics/RectF;Landroid/graphics/RectF;Landroid/graphics/Matrix$ScaleToFit;)Z\n:end_${i}\ngoto :bad\n' +
   '.catch Ljava/lang/NullPointerException; {:try_${i} .. :end_${i}} :caught_${i}\n:caught_${i}\nmove-exception v4\n'
 }
 nulls += 'invoke-virtual {v0}, Landroid/graphics/Matrix;->isIdentity()Z\nmove-result v3\nif-eqz v3, :bad\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Matrix fit alias, null validation or changed matrix"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 os.write_file(dir + '/MatrixFitProbe.smali', '.class public Lorg/vinix/bootstrap/MatrixFitProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check()V', check) + method('private static aliasAndNull()V', nulls) +
  method('private static values(Landroid/graphics/Matrix;[F)V', '
const/16 v0, 9
new-array v0, v0, [F
invoke-virtual {p0, v0}, Landroid/graphics/Matrix;->getValues([F)V
invoke-static {v0, p1}, Ljava/util/Arrays;->equals([F[F)Z
move-result v0
if-nez v0, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Matrix fit scale, translation, skew or perspective"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') + method('private static pixels()V', '
new-instance v8, Landroid/graphics/Matrix;
invoke-direct {v8}, Landroid/graphics/Matrix;-><init>()V
new-instance v9, Landroid/graphics/RectF;
const/high16 v0, 0x3f800000
const/high16 v1, 0x40400000
invoke-direct {v9, v0, v0, v1, v1}, Landroid/graphics/RectF;-><init>(FFFF)V
new-instance v2, Landroid/graphics/RectF;
const/high16 v0, 0x40800000
const/high16 v1, 0x41400000
invoke-direct {v2, v0, v0, v1, v1}, Landroid/graphics/RectF;-><init>(FFFF)V
sget-object v0, Landroid/graphics/Matrix$ScaleToFit;->FILL:Landroid/graphics/Matrix$ScaleToFit;
invoke-virtual {v8, v9, v2, v0}, Landroid/graphics/Matrix;->setRectToRect(Landroid/graphics/RectF;Landroid/graphics/RectF;Landroid/graphics/Matrix$ScaleToFit;)Z
const/16 v0, 16
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Landroid/graphics/Canvas;
invoke-direct {v1, v0}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {v1, v8}, Landroid/graphics/Canvas;->concat(Landroid/graphics/Matrix;)V
new-instance v2, Landroid/graphics/Paint;
invoke-direct {v2}, Landroid/graphics/Paint;-><init>()V
const v3, -0xff0100
invoke-virtual {v2, v3}, Landroid/graphics/Paint;->setColor(I)V
invoke-virtual {v1, v9, v2}, Landroid/graphics/Canvas;->drawRect(Landroid/graphics/RectF;Landroid/graphics/Paint;)V
move-object v8, v0
const/16 v1, 256
new-array v1, v1, [I
const/4 v2, 0
const/16 v3, 16
const/4 v4, 0
const/4 v5, 0
const/16 v6, 16
const/16 v7, 16
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
const/4 v0, 0
:loop
rem-int/lit8 v2, v0, 16
div-int/lit8 v3, v0, 16
const/4 v4, 4
const/16 v5, 12
const/4 v6, 0
if-lt v2, v4, :compare
if-ge v2, v5, :compare
if-lt v3, v4, :compare
if-ge v3, v5, :compare
const v6, -0xff0100
:compare
aget v7, v1, v0
if-ne v7, v6, :bad
add-int/lit8 v0, v0, 1
const/16 v2, 256
if-lt v0, v2, :loop
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Matrix rectangle fit rendered coverage"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
