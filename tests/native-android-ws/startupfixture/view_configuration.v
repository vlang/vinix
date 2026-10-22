// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_view_configuration_probe(dir string) ! {
	config := 'Landroid/view/ViewConfiguration;'
	os.write_file(dir + '/GestureResources.smali', '.class public Lorg/vinix/bootstrap/GestureResources;\n.super Landroid/content/res/Resources;\n' +
		method('public constructor <init>(Landroid/content/Context;)V', '
invoke-virtual {p1}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
new-instance v1, Landroid/util/DisplayMetrics;
invoke-direct {v1}, Landroid/util/DisplayMetrics;-><init>()V
const v2, 0x3fa00000
iput v2, v1, Landroid/util/DisplayMetrics;->density:F
const v2, 0x43480000
iput v2, v1, Landroid/util/DisplayMetrics;->xdpi:F
new-instance v2, Landroid/content/res/Configuration;
invoke-direct {v2}, Landroid/content/res/Configuration;-><init>()V
const/4 v3, 4
iput v3, v2, Landroid/content/res/Configuration;->screenLayout:I
invoke-direct {p0, v0, v1, v2}, Landroid/content/res/Resources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
invoke-virtual {p0}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;
move-result-object v1
const v2, 0x3fa00000
iput v2, v1, Landroid/util/DisplayMetrics;->density:F
const v2, 0x43480000
iput v2, v1, Landroid/util/DisplayMetrics;->xdpi:F
return-void') +
		method('public getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I', '
const-string v0, "dimen"
invoke-virtual {v0, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "android"
invoke-virtual {v0, p3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "config_viewConfigurationTouchSlop"
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0') +
		method('public getDimensionPixelSize(I)I', 'const/4 v0, 1\nif-ne p1, v0, :bad\nconst/16 v0, 11\nreturn v0\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V\nthrow v0'))!
	os.write_file(dir + '/GestureContext.smali', '.class public Lorg/vinix/bootstrap/GestureContext;\n.super Landroid/content/ContextWrapper;\n.field private resources:Landroid/content/res/Resources;\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V\nnew-instance v0, Lorg/vinix/bootstrap/GestureResources;\ninvoke-direct {v0, p1}, Lorg/vinix/bootstrap/GestureResources;-><init>(Landroid/content/Context;)V\niput-object v0, p0, Lorg/vinix/bootstrap/GestureContext;->resources:Landroid/content/res/Resources;\nreturn-void') +
		method('public getResources()Landroid/content/res/Resources;', 'iget-object v0, p0, Lorg/vinix/bootstrap/GestureContext;->resources:Landroid/content/res/Resources;\nreturn-object v0'))!
	mut check := 'new-instance v0, ${config}\ninvoke-direct {v0}, ${config}-><init>()V\n'
	for name, expected in {
		'EdgeSlop':        12
		'WindowTouchSlop': 16
		'TouchSlop':       8
		'HandwritingSlop': 2
	} {
		check += 'invoke-virtual {v0}, ${config}->getScaled${name}()I\nmove-result v1\nconst/16 v2, ${expected}\nconst-string v6, "legacy ${name}"\ninvoke-static {v1, v2, v6}, Lorg/vinix/bootstrap/ViewConfigurationProbe;->expect(IILjava/lang/String;)V\n'
	}
	check += '
:legacy_start
invoke-virtual {v0}, ${config}->getScaledMinimumScalingSpan()I
:legacy_end
.catch Ljava/lang/IllegalStateException; {:legacy_start .. :legacy_end} :legacy_ok
goto :bad
:legacy_ok
move-exception v1
new-instance v3, Lorg/vinix/bootstrap/GestureContext;
invoke-direct {v3, p0}, Lorg/vinix/bootstrap/GestureContext;-><init>(Landroid/content/Context;)V
invoke-static {v3}, ${config}->get(Landroid/content/Context;)${config}
move-result-object v0
'
	for name, expected in {
		'EdgeSlop':                     23
		'DoubleTapSlop':                188
		'WindowTouchSlop':              30
		'TouchSlop':                    11
		'PagingTouchSlop':              22
		'HandwritingSlop':              3
		'HandwritingGestureLineMargin': 20
		'MinimumFlingVelocity':         63
		'MaximumFlingVelocity':         10000
		'MinimumScalingSpan':           213
	} {
		check += 'invoke-virtual {v0}, ${config}->getScaled${name}()I\nmove-result v1\nconst/16 v2, ${expected}\nconst-string v6, "scaled ${name}"\ninvoke-static {v1, v2, v6}, Lorg/vinix/bootstrap/ViewConfigurationProbe;->expect(IILjava/lang/String;)V\n'
	}
	for name in ['Horizontal', 'Vertical'] {
		check += 'invoke-virtual {v0}, ${config}->getScaled${name}ScrollFactor()F\nmove-result v1\nconst/high16 v2, 0x42a00000\ncmpl-float v1, v1, v2\nif-nez v1, :bad\n'
	}
	check += '
invoke-virtual {v3}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v3
invoke-virtual {v3}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;
move-result-object v3
const/high16 v1, 0x40000000
iput v1, v3, Landroid/util/DisplayMetrics;->density:F
invoke-virtual {v0}, ${config}->getScaledEdgeSlop()I
move-result v1
const/16 v2, 23
if-ne v1, v2, :bad
'
	for name, expected in {
		'TouchSlop':            8
		'MinimumFlingVelocity': 50
		'MaximumFlingVelocity': 8000
		'PressedStateDuration': 64
	} {
		check += 'invoke-static {}, ${config}->get${name}()I\nmove-result v1\nconst/16 v2, ${expected}\nif-ne v1, v2, :bad\n'
	}
	for name, sentinel in {
		'Minimum': '0x7fffffff'
		'Maximum': '0x80000000'
	} {
		for input in [['-1', '0', '4098'], ['0', '-1', '4098'], ['0', '0', '0']] {
			check += 'const/16 v1, ${input[0]}\nconst/16 v2, ${input[1]}\nconst/16 v3, ${input[2]}\n' +
				'invoke-virtual {v0, v1, v2, v3}, ${config}->getScaled${name}FlingVelocity(III)I\nmove-result v4\nconst v5, ${sentinel}\nif-ne v4, v5, :bad\n'
		}
	}
	check += '
const/4 v0, 0
:null_start
invoke-static {v0}, ${config}->get(Landroid/content/Context;)${config}
:null_end
.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_ok
goto :bad
:null_ok
move-exception v0
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-VIEW-CONFIG-PASS edge density xlarge resource-override snapshot handwriting fling scroll span-mm legacy invalid-device null"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "view configuration"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	os.write_file(dir + '/ViewConfigurationProbe.smali', '.class public Lorg/vinix/bootstrap/ViewConfigurationProbe;\n.super Ljava/lang/Object;\n' +
		method('private static expect(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v0, p2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0, p0}, Ljava/io/PrintStream;->println(I)V
invoke-virtual {v0, p1}, Ljava/io/PrintStream;->println(I)V
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') + method('public static check(Landroid/content/Context;)V', check))!
}
