// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_matrix_probe(dir string) ! {
 mut check := 'new-instance v0, Landroid/graphics/Matrix;\ninvoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V\n'
 for record in [
  '1,0,0,0,1,0,0,0,1;-2,3,5,11;1',
  '-2,0,7,0,3,11,0,0,1;-3,20,11,44;1',
  '0,-1,0,1,0,0,0,0,1;-11,-2,-3,5;1',
  '1,2,0,0,1,0,0,0,1;4,3,27,11;0',
  '1,0,0,0,1,0,0,0,2;-1,1.5,2.5,5.5;0',
 ] {
  parts := record.split(';')
  check += 'const/16 v1, 9\nnew-array v1, v1, [F\n'
  for i, value in parts[0].split(',') {
   check += 'const/16 v2, ${value}\nint-to-float v2, v2\nconst/16 v3, ${i}\naput v2, v1, v3\n'
  }
  check += 'invoke-virtual {v0, v1}, Landroid/graphics/Matrix;->setValues([F)V\nnew-instance v5, Landroid/graphics/RectF;\n'
  for i, value in parts[1].split(',') {
   check += 'const/16 v${i + 1}, ${int(value.f32() * 2)}\nint-to-float v${i + 1}, v${i + 1}\n' +
    'const/high16 v6, 0x40000000\ndiv-float/2addr v${i + 1}, v6\n'
  }
  check += 'invoke-direct {v5, v1, v2, v3, v4}, Landroid/graphics/RectF;-><init>(FFFF)V\nconst/4 v1, ${parts[2]}\n' +
   'invoke-static {v0, v5, v1}, Lorg/vinix/bootstrap/MatrixProbe;->rect(Landroid/graphics/Matrix;Landroid/graphics/RectF;Z)V\n'
 }
 check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-MATRIX-RECT-PASS identity negative-scale rotation skew perspective in-place"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
 mut rect := '
new-instance v0, Landroid/graphics/RectF;
const/high16 v1, -0x40000000
const/high16 v2, 0x40400000
const/high16 v3, 0x40a00000
const/high16 v4, 0x41300000
invoke-direct {v0, v1, v2, v3, v4}, Landroid/graphics/RectF;-><init>(FFFF)V
new-instance v5, Landroid/graphics/RectF;
invoke-direct {v5}, Landroid/graphics/RectF;-><init>()V
invoke-virtual {p0, v5, v0}, Landroid/graphics/Matrix;->mapRect(Landroid/graphics/RectF;Landroid/graphics/RectF;)Z
move-result v6
if-ne v6, p2, :bad
invoke-virtual {p0, v0}, Landroid/graphics/Matrix;->mapRect(Landroid/graphics/RectF;)Z
move-result v6
if-ne v6, p2, :bad
'
 for name in ['left', 'top', 'right', 'bottom'] {
  rect += 'iget v1, p1, Landroid/graphics/RectF;->${name}:F\n'
  for receiver in ['v0', 'v5'] {
   rect += 'iget v2, ${receiver}, Landroid/graphics/RectF;->${name}:F\ncmpl-float v2, v1, v2\nif-nez v2, :bad\n'
  }
 }
 rect += 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Matrix rectangle bounds or preservation flag"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 os.write_file(dir + '/MatrixProbe.smali', '.class public Lorg/vinix/bootstrap/MatrixProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check()V', check) + method('private static rect(Landroid/graphics/Matrix;Landroid/graphics/RectF;Z)V', rect))!
}
