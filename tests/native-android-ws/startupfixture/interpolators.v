// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import math
import os

// The oracle solves the Bezier equation independently of the framework's
// sampled PathInterpolator implementation. Include the four actual Material
// progress curves encountered while opening a Maps search result.
fn interpolator_curve(x f64, x1 f64, y1 f64, x2 f64, y2 f64) f64 {
	if x <= 0 { return 0 }
	if x >= 1 { return 1 }
	mut low, mut high := 0.0, 1.0
	for _ in 0 .. 64 {
		t := (low + high) / 2
		u := 1 - t
		if 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t < x { low = t } else { high = t }
	}
	t := (low + high) / 2
	u := 1 - t
	return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
}

fn interpolator_float(register string, value f64) string {
	return 'const ${register}, 0x${math.f32_bits(f32(value)):08x}\n'
}

fn interpolator_expected(name string, x f64) f64 {
	return match name {
		'accelerate' { math.pow(x, 4) }
		'decelerate' { 1 - math.pow(1 - x, 3) }
		'accelerate_decelerate' { (1 - math.cos(math.pi * x)) / 2 }
		'cycle' { math.sin(4 * math.pi * x) }
		'anticipate' { x * x * (4 * x - 3) }
		'overshoot' {
			t := x - 1
			t * t * (4 * t + 3) + 1
		}
		'anticipate_overshoot' {
			t := if x < 0.5 { 2 * x } else { 2 * x - 2 }
			if x < 0.5 { t * t * (7 * t - 6) / 2 } else { (t * t * (7 * t + 6) + 2) / 2 }
		}
		'bounce' {
			t := x * 1.1226
			if t < 0.3535 {
				8 * t * t
			} else if t < 0.7408 {
				8 * (t - 0.54719) * (t - 0.54719) + 0.7
			} else if t < 0.9644 {
				8 * (t - 0.8526) * (t - 0.8526) + 0.9
			} else {
				8 * (t - 1.0435) * (t - 1.0435) + 0.95
			}
		}
		'quadratic' {
			// A quadratic Bezier is equivalent to this cubic after degree elevation.
			interpolator_curve(x, 0.4 * 2 / 3, 0, (1 + 0.4 * 2) / 3, 1.0 / 3)
		}
		'path_data' { interpolator_curve(x, 0.2, 0, 0.8, 1) }
		'outside_controls' { interpolator_curve(x, 1.2, 0, 0.8, 1) }
		'vertical' {
			if x < 0.5 { x * 0.4 } else { 0.8 + (x - 0.5) * 0.4 }
		}
		else { x }
	}
}

fn install_interpolator_probe(output string) ! {
	dir := output + '/smali/org/vinix/bootstrap'
	os.mkdir_all(output + '/res/anim')!
	curves := [[0.2, 0.0, 0.8, 1.0], [0.4, 0.0, 1.0, 1.0], [0.0, 0.0, 0.65, 1.0], [0.1, 0.0, 0.45,
		1.0]]
	mut xml := {
		'linear':                '<linearInterpolator/>'
		'accelerate':            '<accelerateInterpolator android:factor="2"/>'
		'decelerate':            '<decelerateInterpolator android:factor="1.5"/>'
		'accelerate_decelerate': '<accelerateDecelerateInterpolator/>'
		'cycle':                 '<cycleInterpolator android:cycles="2"/>'
		'anticipate':            '<anticipateInterpolator android:tension="3"/>'
		'overshoot':             '<overshootInterpolator android:tension="3"/>'
		'anticipate_overshoot':  '<anticipateOvershootInterpolator android:tension="3" android:extraTension="2"/>'
		'bounce':                '<bounceInterpolator/>'
		'quadratic':             '<pathInterpolator android:controlX1="0.4" android:controlY1="0"/>'
		'path_data':             '<pathInterpolator android:pathData="M0,0 C0.2,0 0.8,1 1,1"/>'
		'outside_controls':      '<pathInterpolator android:controlX1="1.2" android:controlY1="0" android:controlX2="0.8" android:controlY2="1"/>'
		'vertical':              '<pathInterpolator android:pathData="M0,0 L0.5,0.2 L0.5,0.8 L1,1"/>'
		'unknown':               '<notAnInterpolator/>'
		'invalid':               '<pathInterpolator android:controlX1="0.2" android:controlY1="0" android:controlX2="0.8"/>'
		'backwards':             '<pathInterpolator android:pathData="M0,0 L0.8,0.2 L0.2,0.8 L1,1"/>'
		'reversing_controls':    '<pathInterpolator android:controlX1="1.2" android:controlY1="0" android:controlX2="-0.2" android:controlY2="1"/>'
		'bad_endpoint':          '<pathInterpolator android:pathData="M0.1,0 L1,1"/>'
		'discontinuous':         '<pathInterpolator android:pathData="M0,0 L0.5,0.5 M0.6,0.6 L1,1"/>'
	}
	for i, values in curves {
		xml['maps${i}'] = '<pathInterpolator android:controlX1="${values[0]}" android:controlY1="${values[1]}" android:controlX2="${values[2]}" android:controlY2="${values[3]}"/>'
	}
	for name, value in xml {
		os.write_file(output + '/res/anim/fixture_interpolator_' + name + '.xml', value.replace('/>', ' xmlns:android="http://schemas.android.com/apk/res/android"/>'))!
	}
	c := 'Lorg/vinix/bootstrap/InterpolatorProbe;'
	r := 'Lorg/vinix/bootstrap/InterpolatorResources;'
	mut source := '.class public ${c}\n.super Ljava/lang/Object;\n'
	source += method('private static load(Landroid/content/Context;Ljava/lang/String;)Landroid/view/animation/Interpolator;', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "anim"
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v2
invoke-virtual {v0, p1, v1, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v0
if-eqz v0, :bad
invoke-static {p0, v0}, Landroid/view/animation/AnimationUtils;->loadInterpolator(Landroid/content/Context;I)Landroid/view/animation/Interpolator;
move-result-object v0
if-eqz v0, :bad
return-object v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "interpolator resource must load a nonnull curve"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	source += method('private static sample(Landroid/view/animation/Interpolator;FF)V', '
invoke-interface {p0, p1}, Landroid/view/animation/Interpolator;->getInterpolation(F)F
move-result v0
sub-float/2addr v0, p2
invoke-static {v0}, Ljava/lang/Math;->abs(F)F
move-result v0
const v1, 0x3b03126f
# Absolute tolerance0.002 includes Android path sampling error.
cmpg-float v0, v0, v1
if-gtz v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "interpolator numerical curve"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	mut check := '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
invoke-virtual {v0}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v1
invoke-virtual {v0}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;
move-result-object v2
invoke-virtual {v0}, Landroid/content/res/Resources;->getConfiguration()Landroid/content/res/Configuration;
move-result-object v3
new-instance v4, ${r}
invoke-direct {v4, v1, v2, v3}, ${r}-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
new-instance v9, Lorg/vinix/bootstrap/InterpolatorContext;
invoke-direct {v9, p0, v4}, Lorg/vinix/bootstrap/InterpolatorContext;-><init>(Landroid/content/Context;Landroid/content/res/Resources;)V
const/4 v0, 0
sput v0, ${r}->closed:I
'
	mut closed := 0
	for name in ['maps0', 'maps1', 'maps2', 'maps3', 'linear', 'accelerate', 'decelerate',
		'accelerate_decelerate', 'cycle', 'anticipate', 'overshoot', 'anticipate_overshoot', 'bounce',
		'quadratic', 'path_data', 'outside_controls', 'vertical', 'maps0'] {
		check += 'const-string v0, "fixture_interpolator_${name}"\ninvoke-static {v9, v0}, ${c}->load(Landroid/content/Context;Ljava/lang/String;)Landroid/view/animation/Interpolator;\nmove-result-object v6\n'
		for x in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
			// A vertical segment has two valid values at its exact X coordinate.
			if name == 'vertical' && x == 0.5 { continue }
			expected := if name.starts_with('maps') {
				v := curves[name[4..].int()]
				interpolator_curve(x, v[0], v[1], v[2], v[3])
			} else {
				interpolator_expected(name, x)
			}
			check += interpolator_float('v0', x) + interpolator_float('v1', expected) + 'invoke-static {v6, v0, v1}, ${c}->sample(Landroid/view/animation/Interpolator;FF)V\n'
		}
		if name.starts_with('maps') {
			for x in [-0.25, 1.25] {
				check += interpolator_float('v0', x) + interpolator_float('v1', if x < 0 {
					0
				} else {
					1
				}) + 'invoke-static {v6, v0, v1}, ${c}->sample(Landroid/view/animation/Interpolator;FF)V\n'
			}
		}
		closed++
		check += 'sget v0, ${r}->closed:I\nconst/16 v1, ${closed}\nif-ne v0, v1, :bad\n'
	}
	for name in ['unknown', 'invalid', 'backwards', 'reversing_controls', 'bad_endpoint',
		'discontinuous'] {
		check += 'const-string v0, "fixture_interpolator_${name}"\n:try_${name}\ninvoke-static {v9, v0}, ${c}->load(Landroid/content/Context;Ljava/lang/String;)Landroid/view/animation/Interpolator;\n:end_${name}\ngoto :bad\n:catch_${name}\nmove-exception v0\n.catch Ljava/lang/RuntimeException; {:try_${name} .. :end_${name}} :catch_${name}\n'
		closed++
		check += 'sget v0, ${r}->closed:I\nconst/16 v1, ${closed}\nif-ne v0, v1, :bad\n'
	}
	// A failed load must leave subsequent parser/resource use intact.
	check += 'const-string v0, "fixture_interpolator_maps0"\ninvoke-static {v9, v0}, ${c}->load(Landroid/content/Context;Ljava/lang/String;)Landroid/view/animation/Interpolator;\nmove-result-object v6\n' +
		interpolator_float('v0', 0.25) + interpolator_float('v1', interpolator_curve(0.25, 0.2, 0, 0.8, 1)) +
		'invoke-static {v6, v0, v1}, ${c}->sample(Landroid/view/animation/Interpolator;FF)V\n'
	closed++
	check += '
const v0, 0x7ffffffe
:try_missing
invoke-static {v9, v0}, Landroid/view/animation/AnimationUtils;->loadInterpolator(Landroid/content/Context;I)Landroid/view/animation/Interpolator;
:end_missing
goto :bad
:catch_missing
move-exception v0
.catch Landroid/content/res/Resources$NotFoundException; {:try_missing .. :end_missing} :catch_missing
sget v0, ${r}->closed:I
const/16 v1, ${closed}
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-INTERPOLATORS-PASS maps-four-curves ten-tags factors endpoints clamps quadratic path-data repeated-load parser-close success-error missing-resource unknown-tag invalid-controls invalid-paths"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "interpolator parser close, error or repeated loading"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	os.write_file(dir + '/InterpolatorProbe.smali', source + method('public static check(Landroid/content/Context;)V', check))!
	os.write_file(dir + '/InterpolatorContext.smali', '.class public Lorg/vinix/bootstrap/InterpolatorContext;\n.super Landroid/content/ContextWrapper;\n.field private resources:Landroid/content/res/Resources;\n' +
		method('public constructor <init>(Landroid/content/Context;Landroid/content/res/Resources;)V', 'invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V\niput-object p2, p0, Lorg/vinix/bootstrap/InterpolatorContext;->resources:Landroid/content/res/Resources;\nreturn-void') +
		method('public getResources()Landroid/content/res/Resources;', 'iget-object v0, p0, Lorg/vinix/bootstrap/InterpolatorContext;->resources:Landroid/content/res/Resources;\nreturn-object v0') +
		method('public getTheme()Landroid/content/res/Resources$Theme;', 'const/4 v0, 0\nreturn-object v0'))!
	os.write_file(dir + '/InterpolatorResources.smali', '.class public ${r}\n.super Landroid/content/res/Resources;\n.field public static closed:I\n' +
		method('public constructor <init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V', 'invoke-direct {p0, p1, p2, p3}, Landroid/content/res/Resources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V\nreturn-void') +
		method('public obtainAttributes(Landroid/util/AttributeSet;[I)Landroid/content/res/TypedArray;', '
# ATL requires its concrete XmlBlock parser for native attribute access. Unwrap
# only for that lookup; loadInterpolator still owns and closes the proxy.
invoke-static {p1}, Ljava/lang/reflect/Proxy;->getInvocationHandler(Ljava/lang/Object;)Ljava/lang/reflect/InvocationHandler;
move-result-object v0
check-cast v0, Lorg/vinix/bootstrap/InterpolatorParser;
iget-object v0, v0, Lorg/vinix/bootstrap/InterpolatorParser;->parser:Landroid/content/res/XmlResourceParser;
invoke-super {p0, v0, p2}, Landroid/content/res/Resources;->obtainAttributes(Landroid/util/AttributeSet;[I)Landroid/content/res/TypedArray;
move-result-object v0
return-object v0') +
		method('public getAnimation(I)Landroid/content/res/XmlResourceParser;', '
invoke-super {p0, p1}, Landroid/content/res/Resources;->getAnimation(I)Landroid/content/res/XmlResourceParser;
move-result-object v0
new-instance v1, Lorg/vinix/bootstrap/InterpolatorParser;
invoke-direct {v1, v0}, Lorg/vinix/bootstrap/InterpolatorParser;-><init>(Landroid/content/res/XmlResourceParser;)V
const/4 v2, 1
new-array v2, v2, [Ljava/lang/Class;
const-class v3, Landroid/content/res/XmlResourceParser;
const/4 v4, 0
aput-object v3, v2, v4
invoke-virtual {v3}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v3
invoke-static {v3, v2, v1}, Ljava/lang/reflect/Proxy;->newProxyInstance(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/content/res/XmlResourceParser;
return-object v0'))!
	os.write_file(dir + '/InterpolatorParser.smali', '.class public Lorg/vinix/bootstrap/InterpolatorParser;\n.super Ljava/lang/Object;\n.implements Ljava/lang/reflect/InvocationHandler;\n.field public parser:Landroid/content/res/XmlResourceParser;\n' +
		method('public constructor <init>(Landroid/content/res/XmlResourceParser;)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Lorg/vinix/bootstrap/InterpolatorParser;->parser:Landroid/content/res/XmlResourceParser;\nreturn-void') +
		method('public invoke(Ljava/lang/Object;Ljava/lang/reflect/Method;[Ljava/lang/Object;)Ljava/lang/Object;', '
invoke-virtual {p2}, Ljava/lang/reflect/Method;->getName()Ljava/lang/String;
move-result-object v0
const-string v1, "close"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :delegate
sget v0, ${r}->closed:I
add-int/lit8 v0, v0, 1
sput v0, ${r}->closed:I
:delegate
iget-object v0, p0, Lorg/vinix/bootstrap/InterpolatorParser;->parser:Landroid/content/res/XmlResourceParser;
invoke-virtual {p2, v0, p3}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
return-object v0'))!
}
