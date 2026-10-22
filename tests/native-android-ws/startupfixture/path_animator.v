// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os
import math

fn install_path_animator_probe(dir string) ! {
 c := 'Lorg/vinix/bootstrap/PathAnimatorProbe;'
 a := 'Landroid/animation/ObjectAnimator;'
 t := 'Landroid/animation/TypeConverter;'
 p := 'Lorg/vinix/bootstrap/PointProperty;'
 os.write_file(dir + '/PointProperty.smali', '.class public ${p}\n.super Landroid/util/Property;\n' +
  method('public constructor <init>()V', 'const-class v0, Landroid/graphics/PointF;\nconst-string v1, "position"\ninvoke-direct {p0, v0, v1}, Landroid/util/Property;-><init>(Ljava/lang/Class;Ljava/lang/String;)V\nreturn-void') +
  method('public get(Ljava/lang/Object;)Ljava/lang/Object;', 'return-object p1') +
  method('public set(Ljava/lang/Object;Ljava/lang/Object;)V', '
check-cast p1, Landroid/graphics/PointF;
check-cast p2, Landroid/graphics/PointF;
iget v0, p2, Landroid/graphics/PointF;->x:F
iget v1, p2, Landroid/graphics/PointF;->y:F
iput v0, p1, Landroid/graphics/PointF;->x:F
iput v1, p1, Landroid/graphics/PointF;->y:F
return-void'))!
 os.write_file(dir + '/PointConverter.smali', '.class public Lorg/vinix/bootstrap/PointConverter;\n.super ${t}\n' +
  method('public constructor <init>()V', 'const-class v0, Landroid/graphics/PointF;\ninvoke-direct {p0, v0, v0}, ${t}-><init>(Ljava/lang/Class;Ljava/lang/Class;)V\nreturn-void') +
  method('public convert(Ljava/lang/Object;)Ljava/lang/Object;', '
check-cast p1, Landroid/graphics/PointF;
iget v0, p1, Landroid/graphics/PointF;->x:F
iget v1, p1, Landroid/graphics/PointF;->y:F
const/high16 v2, 0x40000000
mul-float/2addr v0, v2
const/high16 v2, 0x40400000
mul-float/2addr v1, v2
new-instance v2, Landroid/graphics/PointF;
invoke-direct {v2, v0, v1}, Landroid/graphics/PointF;-><init>(FF)V
return-object v2'))!
 mut check := ''
 // Exact endpoints, non-uniform segments, a cubic, a discontinuous contour,
 // and a zero-length line. Expected fractions are based on arc length.
 for index, row in [
  '0,0;100,0;100,300|0,0,0;0.125,50,0;0.25,100,0;0.5,100,100;1,100,300',
  '0,0;c,0,100,100,100,100,0|0,0,0;0.5,50,75;1,100,0',
  '0,0;100,0;m,300,0;300,100|0.25,50,0;0.75,300,50',
  '7,9;7,9|0,7,9;0.5,7,9;1,7,9',
  '0,0;100,100|0.25,50,75;1,200,300'] {
  parts := row.split('|')
  check += 'new-instance v0, Landroid/graphics/Path;\ninvoke-direct {v0}, Landroid/graphics/Path;-><init>()V\n'
  for n, coords in parts[0].split(';') {
   values := coords.split(',')
   curve := values[0] == 'c'
   moved := values[0] == 'm'
   nums := if curve || moved { values[1..] } else { values }
   for j, value in nums { check += 'const/16 v${j + 1}, ${value}\nint-to-float v${j + 1}, v${j + 1}\n' }
   check += if curve {
    'invoke-virtual/range {v0 .. v6}, Landroid/graphics/Path;->cubicTo(FFFFFF)V\n'
   } else { 'invoke-virtual {v0, v1, v2}, Landroid/graphics/Path;->${if n == 0 || moved { 'moveTo' } else { 'lineTo' }}(FF)V\n' }
  }
  check += if index == 4 { 'new-instance v1, Lorg/vinix/bootstrap/PointConverter;\ninvoke-direct {v1}, Lorg/vinix/bootstrap/PointConverter;-><init>()V\n' } else { 'const/4 v1, 0\n' }
  check += 'invoke-static {v0, v1}, ${c}->create(Landroid/graphics/Path;${t})${a}\nmove-result-object v4\n'
  // Reset after creation to verify that the animator owns a snapshot.
  check += 'invoke-virtual {v0}, Landroid/graphics/Path;->reset()V\n'
  for sample in parts[1].split(';') {
   for j, value in sample.split(',') {
    check += 'const v${j + 1}, 0x${math.f32_bits(value.f32()):08x}\n'
   }
   check += 'invoke-static {v4, v1, v2, v3}, ${c}->at(${a}FFF)V\n'
  }
 }
 check += '
# Clone retains path values while owning an independent temporary point.
invoke-virtual {v4}, ${a}->clone()${a}
move-result-object v5
new-instance v0, Landroid/graphics/PointF;
invoke-direct {v0}, Landroid/graphics/PointF;-><init>()V
invoke-virtual {v5, v0}, ${a}->setTarget(Ljava/lang/Object;)V
const v1, 0x3e800000
const v2, 0x42480000
const v3, 0x42960000
invoke-static {v5, v1, v2, v3}, ${c}->at(${a}FFF)V
invoke-virtual {v4}, ${a}->getTarget()Ljava/lang/Object;
move-result-object v0
const v2, 0x43480000
const v3, 0x43960000
invoke-static {v0, v2, v3}, ${c}->point(Ljava/lang/Object;FF)V
invoke-static {}, ${c}->invalidPaths()V
invoke-static {}, ${c}->scheduled()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-PATH-ANIMATOR-VALUES-PASS arc-length curve contours zero-length endpoints converter clone snapshot null-empty"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void'
 mut text := '.class public ${c}\n.super Landroid/animation/AnimatorListenerAdapter;\n.implements Landroid/animation/ValueAnimator$AnimatorUpdateListener;\n.field private updates:I\n.field private middle:Z\n'
 text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/animation/AnimatorListenerAdapter;-><init>()V\nreturn-void')
 text += method('public static check()V', check)
 text += method('private static create(Landroid/graphics/Path;${t})${a}', '
new-instance v0, Landroid/graphics/PointF;
invoke-direct {v0}, Landroid/graphics/PointF;-><init>()V
new-instance v1, ${p}
invoke-direct {v1}, ${p}-><init>()V
invoke-static {v0, v1, p1, p0}, ${a}->ofObject(Ljava/lang/Object;Landroid/util/Property;${t}Landroid/graphics/Path;)${a}
move-result-object v0
new-instance v1, Landroid/view/animation/LinearInterpolator;
invoke-direct {v1}, Landroid/view/animation/LinearInterpolator;-><init>()V
invoke-virtual {v0, v1}, ${a}->setInterpolator(Landroid/animation/TimeInterpolator;)V
return-object v0')
 text += method('private static at(${a}FFF)V', '
invoke-virtual {p0, p1}, ${a}->setCurrentFraction(F)V
invoke-virtual {p0}, ${a}->getTarget()Ljava/lang/Object;
move-result-object v0
invoke-static {v0, p2, p3}, ${c}->point(Ljava/lang/Object;FF)V
return-void')
 text += method('private static point(Ljava/lang/Object;FF)V', '
check-cast p0, Landroid/graphics/PointF;
iget v0, p0, Landroid/graphics/PointF;->x:F
sub-float/2addr v0, p1
invoke-static {v0}, Ljava/lang/Math;->abs(F)F
move-result v0
const v1, 0x3e800000
cmpg-float v2, v0, v1
if-gtz v2, :bad
iget v0, p0, Landroid/graphics/PointF;->y:F
sub-float/2addr v0, p2
invoke-static {v0}, Ljava/lang/Math;->abs(F)F
move-result v0
cmpg-float v2, v0, v1
if-gtz v2, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Path animator point differs from arc-length position"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 text += method('private static invalidPaths()V', '
const/4 v0, 0
:null_start
invoke-static {v0, v0}, ${c}->create(Landroid/graphics/Path;${t})${a}
:null_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:null_start .. :null_end} :null_ok
:null_ok
move-exception v1
new-instance v1, Landroid/graphics/Path;
invoke-direct {v1}, Landroid/graphics/Path;-><init>()V
:empty_start
invoke-static {v1, v0}, ${c}->create(Landroid/graphics/Path;${t})${a}
:empty_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:empty_start .. :empty_end} :empty_ok
:empty_ok
move-exception v1
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Path animator must reject null and empty paths"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 text += method('private static scheduled()V', '
new-instance v0, Landroid/graphics/Path;
invoke-direct {v0}, Landroid/graphics/Path;-><init>()V
const/4 v1, 0
invoke-virtual {v0, v1, v1}, Landroid/graphics/Path;->moveTo(FF)V
const v2, 0x42c80000
invoke-virtual {v0, v2, v2}, Landroid/graphics/Path;->lineTo(FF)V
invoke-static {v0, v1}, ${c}->create(Landroid/graphics/Path;${t})${a}
move-result-object v0
new-instance v1, ${c}
invoke-direct {v1}, ${c}-><init>()V
invoke-virtual {v0, v1}, ${a}->addListener(Landroid/animation/Animator$AnimatorListener;)V
invoke-virtual {v0, v1}, ${a}->addUpdateListener(Landroid/animation/ValueAnimator$AnimatorUpdateListener;)V
const-wide/16 v2, 300
invoke-virtual {v0, v2, v3}, ${a}->setDuration(J)${a}
invoke-virtual {v0}, ${a}->start()V
return-void')
 text += method('public onAnimationUpdate(Landroid/animation/ValueAnimator;)V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
iget v0, p0, ${c}->updates:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->updates:I
invoke-virtual {p1}, Landroid/animation/ValueAnimator;->getAnimatedValue()Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/graphics/PointF;
iget v0, v0, Landroid/graphics/PointF;->x:F
const/4 v1, 0
cmpg-float v1, v0, v1
if-lez v1, :done
const v1, 0x42c80000
cmpg-float v1, v0, v1
if-gez v1, :done
const/4 v1, 1
iput-boolean v1, p0, ${c}->middle:Z
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Path animation callback must use main looper"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 text += method('public onAnimationEnd(Landroid/animation/Animator;)V', '
iget v0, p0, ${c}->updates:I
const/4 v1, 2
if-lt v0, v1, :bad
iget-boolean v0, p0, ${c}->middle:Z
if-eqz v0, :bad
check-cast p1, ${a}
invoke-virtual {p1}, ${a}->getTarget()Ljava/lang/Object;
move-result-object v0
const v1, 0x42c80000
invoke-static {v0, v1, v1}, ${c}->point(Ljava/lang/Object;FF)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-PATH-ANIMATOR-FRAMES-PASS main-looper intermediate-frames applied-final-property end-callback"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Path animator did not schedule intermediate frames"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 os.write_file(dir + '/PathAnimatorProbe.smali', text)!
}
