// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import math
import os

fn install_matrix_inversion_probe(dir string) ! {
 mut check := ''
 for values in [
  '1,0,0,0,1,0,0,0,1',
  '-2,0,7,0,3,11,0,0,1',
  '0,-1,5,1,0,-3,0,0,1',
  '1,2,7,3,4,11,0,0,1',
  '2,1,3,1,3,-2,0.125,-0.25,2',
  '0.000001,0,7,0,0.000001,11,0,0,1',
  '1,2,3,0,1,4,5,6,0',
  '0,0,0,0,1,0,0,0,1',
  '1,2,3,2,4,6,0,0,1',
  '1e-40,0,0,0,1,0,0,0,1',
  '1,0,NaN,0,1,0,0,0,1',
  '1,0,0,0,1,0,0,0,Infinity',
 ] {
  check += 'const/16 v0, 9\nnew-array v0, v0, [F\n'
  for index, number in values.split(',') {
   bits := if number == 'NaN' { u32(0x7fc00000) } else if number == 'Infinity' { u32(0x7f800000) } else { math.f32_bits(number.f32()) }
   check += 'const v1, 0x${bits:08x}\nconst/16 v2, ${index}\naput v1, v0, v2\n'
  }
  success := if values in ['0,0,0,0,1,0,0,0,1', '1,2,3,2,4,6,0,0,1', '1e-40,0,0,0,1,0,0,0,1', '1,0,NaN,0,1,0,0,0,1', '1,0,0,0,1,0,0,0,Infinity'] { 0 } else { 1 }
  check += 'const/4 v1, ${success}\ninvoke-static {v0, v1}, Lorg/vinix/bootstrap/MatrixInverseProbe;->inverse([FZ)V\n'
 }
 check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-MATRIX-INVERSE-PASS affine perspective small-scale in-place roundtrip singular unchanged nonfinite overflow"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
 os.write_file(dir + '/MatrixInverseProbe.smali', '.class public Lorg/vinix/bootstrap/MatrixInverseProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check()V', check) + method('private static inverse([FZ)V', '
new-instance v0, Landroid/graphics/Matrix;
invoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V
invoke-virtual {v0, p0}, Landroid/graphics/Matrix;->setValues([F)V
new-instance v1, Landroid/graphics/Matrix;
invoke-direct {v1}, Landroid/graphics/Matrix;-><init>()V
const/high16 v2, 0x40e00000
const/high16 v3, 0x41300000
invoke-virtual {v1, v2, v3}, Landroid/graphics/Matrix;->setTranslate(FF)V
const/16 v2, 9
new-array v2, v2, [F
invoke-virtual {v1, v2}, Landroid/graphics/Matrix;->getValues([F)V
invoke-virtual {v0, v1}, Landroid/graphics/Matrix;->invert(Landroid/graphics/Matrix;)Z
move-result v3
if-ne v3, p1, :bad
const/16 v3, 9
new-array v3, v3, [F
invoke-virtual {v0, v3}, Landroid/graphics/Matrix;->getValues([F)V
invoke-static {p0, v3}, Ljava/util/Arrays;->equals([F[F)Z
move-result v4
if-eqz v4, :bad
if-eqz p1, :failed
new-instance v4, Landroid/graphics/Matrix;
invoke-direct {v4}, Landroid/graphics/Matrix;-><init>()V
invoke-virtual {v4, v0, v1}, Landroid/graphics/Matrix;->setConcat(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z
invoke-static {v4}, Lorg/vinix/bootstrap/MatrixInverseProbe;->identity(Landroid/graphics/Matrix;)V
invoke-virtual {v4, v1, v0}, Landroid/graphics/Matrix;->setConcat(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z
invoke-static {v4}, Lorg/vinix/bootstrap/MatrixInverseProbe;->identity(Landroid/graphics/Matrix;)V
invoke-virtual {v0, v0}, Landroid/graphics/Matrix;->invert(Landroid/graphics/Matrix;)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v0, v3}, Landroid/graphics/Matrix;->getValues([F)V
invoke-virtual {v1, v2}, Landroid/graphics/Matrix;->getValues([F)V
invoke-static {v2, v3}, Ljava/util/Arrays;->equals([F[F)Z
move-result v4
if-eqz v4, :bad
return-void
:failed
invoke-virtual {v1, v3}, Landroid/graphics/Matrix;->getValues([F)V
invoke-static {v2, v3}, Ljava/util/Arrays;->equals([F[F)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v0, v0}, Landroid/graphics/Matrix;->invert(Landroid/graphics/Matrix;)Z
move-result v4
if-nez v4, :bad
invoke-virtual {v0, v3}, Landroid/graphics/Matrix;->getValues([F)V
invoke-static {p0, v3}, Ljava/util/Arrays;->equals([F[F)Z
move-result v4
if-eqz v4, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Matrix inversion result, aliasing or unchanged destination"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static identity(Landroid/graphics/Matrix;)V', '
const/16 v0, 9
new-array v0, v0, [F
invoke-virtual {p0, v0}, Landroid/graphics/Matrix;->getValues([F)V
const/4 v1, 0
:loop
aget v2, v0, v1
const/4 v3, 0
rem-int/lit8 v4, v1, 4
if-nez v4, :compare
const/high16 v3, 0x3f800000
:compare
sub-float/2addr v2, v3
invoke-static {v2}, Ljava/lang/Math;->abs(F)F
move-result v2
const v3, 0x38d1b717
cmpg-float v2, v2, v3
if-gtz v2, :bad
add-int/lit8 v1, v1, 1
const/16 v2, 9
if-lt v1, v2, :loop
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Matrix inverse round trip"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
