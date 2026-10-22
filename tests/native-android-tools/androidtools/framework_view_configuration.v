// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn view_configuration_method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 8\n' + body + '\n.end method\n'
}

// Snapshot gesture thresholds from the visual context. Framework resource
// overlays take precedence over the Android defaults; old resource packages
// can lack the newer handwriting dimensions.
fn framework_view_configuration(smali string) ! {
	class := 'Landroid/view/ViewConfiguration;'
	resources := 'Landroid/content/res/Resources;'
	path := smali + '/android/view/ViewConfiguration.smali'
	mut text := os.read_file(path)!
	text += '\n.field private vinixContext:Z\n'
	mut legacy := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
	mut context := 'invoke-direct {p0}, ${class}-><init>()V\nconst/4 v0, 1\niput-boolean v0, p0, ${class}->vinixContext:Z\n' +
		'invoke-virtual {p1}, Landroid/content/Context;->getResources()${resources}\nmove-result-object v0\n' +
		'invoke-virtual {v0}, ${resources}->getDisplayMetrics()Landroid/util/DisplayMetrics;\nmove-result-object v1\n' +
		'iget v2, v1, Landroid/util/DisplayMetrics;->density:F\nmove v3, v2\n' +
		'invoke-virtual {v0}, ${resources}->getConfiguration()Landroid/content/res/Configuration;\nmove-result-object v4\n' +
		'iget v4, v4, Landroid/content/res/Configuration;->screenLayout:I\nand-int/lit8 v4, v4, 15\nconst/4 v5, 4\nif-lt v4, v5, :size_ready\n' +
		'const/high16 v5, 0x3fc00000\nmul-float/2addr v3, v5\n:size_ready\n'
	// Name, fallback in dp, framework dimen (or size-adjusted density).
	for row in [
		['EdgeSlop', '12', 'size'],
		['FadingEdgeLength', '12', 'size'],
		['DoubleTapSlop', '100', 'size'],
		['WindowTouchSlop', '16', 'size'],
		['TouchSlop', '8', 'config_viewConfigurationTouchSlop'],
		['HandwritingSlop', '2', 'config_viewConfigurationHandwritingSlop'],
		['HandwritingGestureLineMargin', '16', 'config_viewConfigurationHandwritingGestureLineMargin'],
		['HoverSlop', '4', 'config_viewConfigurationHoverSlop'],
		['MinimumFlingVelocity', '50', 'config_viewMinFlingVelocity'],
		['MaximumFlingVelocity', '8000', 'config_viewMaxFlingVelocity'],
		['HorizontalScrollFactor', '64', 'config_horizontalScrollFactor'],
		['VerticalScrollFactor', '64', 'config_verticalScrollFactor'],
		['MinimumScalingSpan', '0', 'config_minScalingSpan'],
	] {
		name, fallback, resource := row[0], row[1], row[2]
		text += '.field private vinix${name}:I\n'
		legacy += 'const/16 v0, ${fallback}\niput v0, p0, ${class}->vinix${name}:I\n'
		if name == 'MinimumScalingSpan' {
			// Android's default is 27 mm, independent of the logical density.
			context += 'iget v4, v1, Landroid/util/DisplayMetrics;->xdpi:F\nconst v5, 0x3f881021\nmul-float/2addr v4, v5\n'
		} else {
			context += 'const/16 v4, ${fallback}\nint-to-float v4, v4\nmul-float/2addr v4, ' + if resource == 'size' {
				'v3\n'
			} else {
				'v2\n'
			}
		}
		context += 'const/high16 v5, 0x3f000000\nadd-float/2addr v4, v5\nfloat-to-int v4, v4\n'
		if resource != 'size' {
			context += 'const-string v5, "${resource}"\ninvoke-static {v0, v5, v4}, ${class}->vinixDimension(${resources}Ljava/lang/String;I)I\nmove-result v4\n'
		}
		context += 'iput v4, p0, ${class}->vinix${name}:I\n'
		result := if name.ends_with('ScrollFactor') { 'F' } else { 'I' }
		mut body := ''
		if name == 'MinimumScalingSpan' {
			body += 'iget-boolean v0, p0, ${class}->vinixContext:Z\nif-nez v0, :context\n' +
				'new-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "Minimum scaling span requires a Context"\n' +
				'invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0\n:context\n'
		}
		body += 'iget v0, p0, ${class}->vinix${name}:I\n'
		if result == 'F' { body += 'int-to-float v0, v0\n' }
		signature := 'getScaled${name}()${result}'
		text = framework_replace_method(text, signature, view_configuration_method('public ' + signature, body + 'return v0'))!
	}
	text = framework_replace_method(text, '<init>()V', view_configuration_method('public constructor <init>()V', legacy + 'return-void'))!
	text += view_configuration_method('private constructor <init>(Landroid/content/Context;)V', context + 'return-void')
	text = framework_replace_method(text, 'get(Landroid/content/Context;)${class}', view_configuration_method('public static get(Landroid/content/Context;)${class}',
		'new-instance v0, ${class}\ninvoke-direct {v0, p0}, ${class}-><init>(Landroid/content/Context;)V\nreturn-object v0'))!
	text += view_configuration_method('private static vinixDimension(${resources}Ljava/lang/String;I)I', '
const-string v0, "dimen"
const-string v1, "android"
invoke-virtual {p0, p1, v0, v1}, ${resources}->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v0
if-eqz v0, :fallback
invoke-virtual {p0, v0}, ${resources}->getDimensionPixelSize(I)I
move-result v0
return v0
:fallback
return p2')
	text = framework_replace_method(text, 'getScaledPagingTouchSlop()I', view_configuration_method('public getScaledPagingTouchSlop()I',
		'iget v0, p0, ${class}->vinixTouchSlop:I\nmul-int/lit8 v0, v0, 2\nreturn v0'))!
	for name, value in {
		'PressedStateDuration': 64
		'EdgeSlop':             12
		'TouchSlop':            8
		'WindowTouchSlop':      16
		'MinimumFlingVelocity': 50
		'MaximumFlingVelocity': 8000
	} {
		signature := 'get${name}()I'
		text = framework_replace_method(text, signature, view_configuration_method('public static ' + signature, 'const/16 v0, ${value}\nreturn v0'))!
	}
	// Use enumerated devices/ranges rather than the provider's permissive
	// getDevice/getMotionRange stubs. No rotary input is exposed by native WS.
	text += view_configuration_method('private static vinixFlingDevice(III)Z', '
invoke-static {}, Landroid/view/InputDevice;->getDeviceIds()[I
move-result-object v0
const/4 v1, 0
:device
array-length v2, v0
if-ge v1, v2, :invalid
aget v2, v0, v1
if-eq v2, p0, :found
add-int/lit8 v1, v1, 1
goto :device
:found
const/high16 v0, 0x400000
if-eq p2, v0, :invalid
invoke-static {p0}, Landroid/view/InputDevice;->getDevice(I)Landroid/view/InputDevice;
move-result-object v0
if-eqz v0, :invalid
invoke-virtual {v0}, Landroid/view/InputDevice;->getSources()I
move-result v1
and-int/2addr v1, p2
if-ne v1, p2, :invalid
invoke-virtual {v0}, Landroid/view/InputDevice;->getMotionRanges()Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v0
:range
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :invalid
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/view/InputDevice$MotionRange;
invoke-virtual {v1}, Landroid/view/InputDevice$MotionRange;->getAxis()I
move-result v1
if-ne v1, p1, :range
const/4 v0, 1
return v0
:invalid
const/4 v0, 0
return v0')
	for name in ['Minimum', 'Maximum'] {
		signature := 'getScaled${name}FlingVelocity(III)I'
		sentinel := if name == 'Minimum' { '0x7fffffff' } else { '0x80000000' }
		text = framework_replace_method(text, signature, view_configuration_method('public ' + signature,
			'invoke-static {p1, p2, p3}, ${class}->vinixFlingDevice(III)Z\nmove-result v0\nif-nez v0, :valid\nconst v0, ${sentinel}\nreturn v0\n:valid\n' +
				'invoke-virtual {p0}, ${class}->getScaled${name}FlingVelocity()I\nmove-result v0\nreturn v0'))!
	}
	os.write_file(path, text)!
}
