// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Path values use the native WS geometry, sampled by arc length. The snapshot
// belongs to Java, so subsequent mutations of the Path cannot alter an animator.
fn framework_path_animator(smali string) ! {
 c := 'Landroid/animation/VinixPathValues;'
 b := 'Landroid/animation/PropertyValuesHolder;'
 t := 'Landroid/animation/TypeConverter;'
 mut converter := '.class public abstract ${t}\n.super Ljava/lang/Object;\n.field private source:Ljava/lang/Class;\n.field private target:Ljava/lang/Class;\n'
 converter += time_animator_method('public constructor <init>(Ljava/lang/Class;Ljava/lang/Class;)V', 0,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${t}->source:Ljava/lang/Class;\niput-object p2, p0, ${t}->target:Ljava/lang/Class;\nreturn-void')
 for name, field in {'Source': 'source', 'Target': 'target'} {
  converter += time_animator_method('get${name}Type()Ljava/lang/Class;', 1,
   'iget-object v0, p0, ${t}->${field}:Ljava/lang/Class;\nreturn-object v0')
 }
 converter += '.method public abstract convert(Ljava/lang/Object;)Ljava/lang/Object;\n.end method\n'
 os.write_file(smali + '/android/animation/TypeConverter.smali', converter)!
 mut text := '.class public final ${c}\n.super ${b}\n.field private samples:[F\n.field private converter:${t}\n.field private point:Landroid/graphics/PointF;\n.field private animated:Ljava/lang/Object;\n.field private fraction:F\n' +
  // The object argument roots Path for the entire JNI call, including allocation.
  '.method private static native nativePath(Landroid/graphics/Path;J)[F\n.end method\n'
 text += time_animator_method('public constructor <init>(Landroid/util/Property;${t}Landroid/graphics/Path;)V', 3, '
invoke-direct {p0}, ${b}-><init>()V
if-eqz p3, :empty
invoke-virtual {p3}, Landroid/graphics/Path;->getGskPath()J
move-result-wide v0
invoke-static {p3, v0, v1}, ${c}->nativePath(Landroid/graphics/Path;J)[F
move-result-object v0
invoke-direct {p0, p1, p2, v0}, ${c}->init(Landroid/util/Property;${t}[F)V
return-void
:empty
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "The path must not be null or empty"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0')
 text += time_animator_method('private constructor <init>(Landroid/util/Property;${t}[F)V', 0,
  'invoke-direct {p0}, ${b}-><init>()V\ninvoke-direct {p0, p1, p2, p3}, ${c}->init(Landroid/util/Property;${t}[F)V\nreturn-void')
 text += time_animator_method('private init(Landroid/util/Property;${t}[F)V', 1, '
invoke-virtual {p0, p1}, ${b}->setProperty(Landroid/util/Property;)V
iput-object p2, p0, ${c}->converter:${t}
iput-object p3, p0, ${c}->samples:[F
new-instance v0, Landroid/graphics/PointF;
invoke-direct {v0}, Landroid/graphics/PointF;-><init>()V
iput-object v0, p0, ${c}->point:Landroid/graphics/PointF;
return-void')
 // Binary search preserves exact endpoints and contour discontinuities. Values
 // outside [0,1] extrapolate, as required by overshooting interpolators.
 text += time_animator_method('private sample(F)Landroid/graphics/PointF;', 8, '
iget-object v0, p0, ${c}->samples:[F
array-length v1, v0
div-int/lit8 v1, v1, 3
add-int/lit8 v1, v1, -1
const/4 v2, 0
const/4 v3, 0
cmpg-float v4, p1, v3
if-eqz v4, :range
if-ltz v4, :before
const/high16 v3, 0x3f800000
cmpl-float v4, p1, v3
if-gtz v4, :after
if-eqz v4, :last
move v3, v1
:search
if-gt v2, v3, :between
add-int v4, v2, v3
div-int/lit8 v4, v4, 2
mul-int/lit8 v5, v4, 3
aget v6, v0, v5
cmpg-float v7, p1, v6
if-ltz v7, :lower
if-gtz v7, :higher
move v2, v4
move v3, v4
goto :range
:lower
add-int/lit8 v3, v4, -1
goto :search
:higher
add-int/lit8 v2, v4, 1
goto :search
:between
move v4, v2
move v2, v3
move v3, v4
goto :range
:before
const/4 v3, 1
goto :range
:after
move v3, v1
add-int/lit8 v2, v1, -1
goto :range
:last
move v2, v1
move v3, v1
:range
invoke-direct {p0, p1, v2, v3}, ${c}->interpolate(FII)Landroid/graphics/PointF;
move-result-object v0
return-object v0')
 text += time_animator_method('private interpolate(FII)Landroid/graphics/PointF;', 8, '
iget-object v0, p0, ${c}->samples:[F
mul-int/lit8 p2, p2, 3
mul-int/lit8 p3, p3, 3
const/4 v1, 0
if-eq p2, p3, :coordinates
aget v2, v0, p2
aget v3, v0, p3
sub-float/2addr v3, v2
const/4 v4, 0
cmpl-float v4, v3, v4
if-eqz v4, :coordinates
sub-float v1, p1, v2
div-float/2addr v1, v3
:coordinates
add-int/lit8 v2, p2, 1
add-int/lit8 v3, p3, 1
aget v4, v0, v2
aget v5, v0, v3
sub-float/2addr v5, v4
mul-float/2addr v5, v1
add-float/2addr v4, v5
add-int/lit8 v2, v2, 1
add-int/lit8 v3, v3, 1
aget v5, v0, v2
aget v6, v0, v3
sub-float/2addr v6, v5
mul-float/2addr v6, v1
add-float/2addr v5, v6
iget-object v7, p0, ${c}->point:Landroid/graphics/PointF;
iput v4, v7, Landroid/graphics/PointF;->x:F
iput v5, v7, Landroid/graphics/PointF;->y:F
return-object v7')
 text += time_animator_method('public calculateValue(F)V', 2, '
iput p1, p0, ${c}->fraction:F
invoke-direct {p0, p1}, ${c}->sample(F)Landroid/graphics/PointF;
move-result-object v0
iget-object v1, p0, ${c}->converter:${t}
if-eqz v1, :store
invoke-virtual {v1, v0}, ${t}->convert(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
:store
iput-object v0, p0, ${c}->animated:Ljava/lang/Object;
return-void')
 text += time_animator_method('public getAnimatedValue()Ljava/lang/Object;', 1,
  'iget-object v0, p0, ${c}->animated:Ljava/lang/Object;\nreturn-object v0')
 text += time_animator_method('public setAnimatedValue(Ljava/lang/Object;)V', 2, '
iget-object v0, p0, ${b}->property:Landroid/util/Property;
iget-object v1, p0, ${c}->animated:Ljava/lang/Object;
invoke-virtual {v0, p1, v1}, Landroid/util/Property;->set(Ljava/lang/Object;Ljava/lang/Object;)V
return-void')
 text += time_animator_method('public clone()${b}', 4, '
new-instance v0, ${c}
iget-object v1, p0, ${b}->property:Landroid/util/Property;
iget-object v2, p0, ${c}->converter:${t}
iget-object v3, p0, ${c}->samples:[F
invoke-direct {v0, v1, v2, v3}, ${c}-><init>(Landroid/util/Property;${t}[F)V
iget v1, p0, ${c}->fraction:F
invoke-virtual {v0, v1}, ${c}->calculateValue(F)V
return-object v0')
 os.write_file(smali + '/android/animation/VinixPathValues.smali', text)!
 holder := smali + '/android/animation/PropertyValuesHolder.smali'
 os.write_file(holder, framework_replace_method(os.read_file(holder)!,
  'ofObject(Landroid/util/Property;${t}Landroid/graphics/Path;)${b}',
  time_animator_method('public static ofObject(Landroid/util/Property;${t}Landroid/graphics/Path;)${b}', 1,
   'new-instance v0, ${c}\ninvoke-direct {v0, p0, p1, p2}, ${c}-><init>(Landroid/util/Property;${t}Landroid/graphics/Path;)V\nreturn-object v0'))!)!
 animator := smali + '/android/animation/ObjectAnimator.smali'
 os.write_file(animator, framework_replace_method(os.read_file(animator)!,
  'ofObject(Ljava/lang/Object;Landroid/util/Property;${t}Landroid/graphics/Path;)Landroid/animation/ObjectAnimator;',
  time_animator_method('public static ofObject(Ljava/lang/Object;Landroid/util/Property;${t}Landroid/graphics/Path;)Landroid/animation/ObjectAnimator;', 3, '
invoke-static {p1, p2, p3}, ${b}->ofObject(Landroid/util/Property;${t}Landroid/graphics/Path;)${b}
move-result-object v0
const/4 v1, 1
new-array v1, v1, [Landroid/animation/PropertyValuesHolder;
const/4 v2, 0
aput-object v0, v1, v2
invoke-static {p0, v1}, Landroid/animation/ObjectAnimator;->ofPropertyValuesHolder(Ljava/lang/Object;[Landroid/animation/PropertyValuesHolder;)Landroid/animation/ObjectAnimator;
move-result-object v0
return-object v0'))!)!
}
