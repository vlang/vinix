// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK hint API, measurement and real Canvas pixel regression.
module main

import crypto.sha256
import json2
import os
import time

const probe_class = 'Lorg/vinix/bootstrap/HintProbe;'
const widget = 'Landroid/widget/TextView;'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn eq(a string, b string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${a}, ${b}, v9}, ${probe_class}->equal(IILjava/lang/String;)V\n'
}

fn same(a string, b string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${a}, ${b}, v9}, ${probe_class}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn marker(name string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-TEXT-HINT-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn create(class string, register string) string {
	return 'new-instance ${register}, Landroid/widget/${class};\nconst/4 v1, 0\nconst v2, @NEUTRAL@\ninvoke-direct {${register}, p0, v1, v1, v2}, Landroid/widget/${class};-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n'
}

fn set_hint(register string, text string) string {
	return 'const-string v1, "${text}"\ninvoke-virtual {${register}, v1}, ${widget}->setHint(Ljava/lang/CharSequence;)V\n'
}

fn set_text(register string, text string) string {
	return 'const-string v1, "${text}"\ninvoke-virtual {${register}, v1}, ${widget}->setText(Ljava/lang/CharSequence;)V\n'
}

fn ink(register string, color string, wanted bool, label string) string {
	return 'const v1, ${color}\nconst/4 v2, ' + if wanted { '1' } else { '0' } + '\nconst-string v3, "${label}"\ninvoke-static {${register}, v1, v2, v3}, ${probe_class}->ink(Landroid/view/View;IZLjava/lang/String;)[I\nmove-result-object v6\n'
}

fn helpers() string {
	mut s := method('private static equal(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Text hint: "
invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " actual="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " expected="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void', 2)
	s += method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', '
if-eq p0, p1, :ok
const/4 v0, 0
const/4 v1, 1
invoke-static {v0, v1, p2}, ${probe_class}->equal(IILjava/lang/String;)V
:ok
return-void', 2)
	s += method('private static configure(Landroid/widget/TextView;)V', '
const v0, 0xffff0000
invoke-virtual {p0, v0}, ${widget}->setTextColor(I)V
const v0, 0xffff00ff
invoke-virtual {p0, v0}, ${widget}->setHintTextColor(I)V
const v0, 0x41b00000
invoke-virtual {p0, v0}, ${widget}->setTextSize(F)V
const/4 v0, 1
invoke-virtual {p0, v0}, ${widget}->setSingleLine(Z)V
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/view/View;->setBackgroundColor(I)V
const/16 v0, 11
const/4 v1, 7
const/16 v2, 17
const/16 v3, 13
invoke-virtual {p0, v0, v1, v2, v3}, Landroid/view/View;->setPadding(IIII)V
const/16 v0, 0x33
invoke-virtual {p0, v0}, ${widget}->setGravity(I)V
const/4 v0, 0
const/16 v1, 240
const/16 v2, 120
invoke-virtual {p0, v0, v0, v1, v2}, Landroid/view/View;->layout(IIII)V
return-void', 4)
	s += method('private static raster(Landroid/view/View;)[I', '
const/16 v1, 240
const/16 v2, 120
sget-object v3, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v1, v2, v3}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
const/4 v0, 0
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v9, Landroid/graphics/Canvas;
invoke-direct {v9, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v9}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/16 v0, 28800
new-array v10, v0, [I
move-object v0, v8
move-object v1, v10
const/4 v2, 0
const/16 v3, 240
const/4 v4, 0
const/4 v5, 0
const/16 v6, 240
const/16 v7, 120
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
return-object v10', 12)
	// Return pure-color count and its bounding box, independent of font raster details.
	s += method('private static pixels(Landroid/view/View;I)[I', '
invoke-static {p0}, ${probe_class}->raster(Landroid/view/View;)[I
move-result-object v10
const/4 v0, 5
new-array v11, v0, [I
const/4 v0, 1
const/16 v1, 240
aput v1, v11, v0
const/4 v0, 2
const/16 v1, 120
aput v1, v11, v0
const/4 v0, 3
const/4 v1, -1
aput v1, v11, v0
const/4 v0, 4
aput v1, v11, v0
const/4 v0, 0
const/4 v4, 0
const v5, 0x01000000
if-ne p1, v5, :color_mask
const/4 v4, 1
:color_mask
const v9, 0xffffff
and-int/2addr p1, v9
:scan
array-length v1, v10
if-ge v0, v1, :done
aget v5, v10, v0
ushr-int/lit8 v2, v5, 24
if-eqz v2, :next
if-nez v4, :matched
and-int/2addr v5, v9
if-ne v5, p1, :next
:matched
const/4 v1, 0
aget v2, v11, v1
add-int/lit8 v2, v2, 1
aput v2, v11, v1
rem-int/lit16 v6, v0, 240
div-int/lit16 v7, v0, 240
const/4 v1, 1
aget v2, v11, v1
if-ge v6, v2, :min_y
aput v6, v11, v1
:min_y
const/4 v1, 2
aget v2, v11, v1
if-ge v7, v2, :max_x
aput v7, v11, v1
:max_x
const/4 v1, 3
aget v2, v11, v1
if-le v6, v2, :max_y
aput v6, v11, v1
:max_y
const/4 v1, 4
aget v2, v11, v1
if-le v7, v2, :next
aput v7, v11, v1
:next
add-int/lit8 v0, v0, 1
goto :scan
:done
return-object v11', 12)
	s += method('private static ink(Landroid/view/View;IZLjava/lang/String;)[I', '
invoke-static {p0, p1}, ${probe_class}->pixels(Landroid/view/View;I)[I
move-result-object v0
const/4 v1, 0
aget v1, v0, v1
const/4 v2, 0
if-lez v1, :counted
const/4 v2, 1
:counted
invoke-static {v2, p2, p3}, ${probe_class}->equal(IILjava/lang/String;)V
return-object v0', 3)
	s += method('private static compare([I[ILjava/lang/String;)V', '
const/4 v0, 0
:next
aget v1, p0, v0
aget v2, p1, v0
invoke-static {v1, v2, p2}, ${probe_class}->equal(IILjava/lang/String;)V
add-int/lit8 v0, v0, 1
const/4 v1, 5
if-lt v0, v1, :next
return-void', 3)
	s += method('private static sameRaster([I[ILjava/lang/String;)V', '
invoke-static {p0, p1}, Ljava/util/Arrays;->equals([I[I)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1, p2}, ${probe_class}->equal(IILjava/lang/String;)V
return-void', 2)
	s += method('private static traceAbsent()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :good
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
const/4 v0, 0
const/4 v1, 1
const-string v3, "trace variables must be absent"
invoke-static {v0, v1, v3}, ${probe_class}->equal(IILjava/lang/String;)V
:good
' + marker('TRACE-ENV-ABSENT') + 'return-void', 4)
	return s
}

fn api_probe() string {
	mut b := ''
	for class in ['TextView', 'EditText'] {
		b += create(class, 'v0') + 'invoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v1\nconst/4 v2, 0\n' + same('v1', 'v2', class + ' initial null hint')
		b += 'new-instance v5, Landroid/text/SpannedString;\nconst-string v1, "Original hint H"\ninvoke-direct {v5, v1}, Landroid/text/SpannedString;-><init>(Ljava/lang/CharSequence;)V\ninvoke-virtual {v0, v5}, ${widget}->setHint(Ljava/lang/CharSequence;)V\ninvoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v1\n' + same('v1', 'v5', class + ' retains immutable Spanned identity')
		b += 'new-instance v5, Ljava/lang/StringBuilder;\nconst-string v1, "Snapshot hint H"\ninvoke-direct {v5, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V\ninvoke-virtual {v0, v5}, ${widget}->setHint(Ljava/lang/CharSequence;)V\nconst-string v1, " mutated"\ninvoke-virtual {v5, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\ninvoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v1\nconst-string v2, "Snapshot hint H"\ninvoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', class + ' snapshots mutable sequence')
		b += 'new-instance v5, Landroid/text/SpannableString;\nconst-string v1, "Spanned hint H"\ninvoke-direct {v5, v1}, Landroid/text/SpannableString;-><init>(Ljava/lang/CharSequence;)V\nnew-instance v6, Landroid/text/style/ForegroundColorSpan;\nconst v1, 0xff123456\ninvoke-direct {v6, v1}, Landroid/text/style/ForegroundColorSpan;-><init>(I)V\nconst/4 v1, 0\nconst/4 v2, 7\nconst/16 v3, 33\ninvoke-virtual {v5, v6, v1, v2, v3}, Landroid/text/SpannableString;->setSpan(Ljava/lang/Object;III)V\ninvoke-virtual {v0, v5}, ${widget}->setHint(Ljava/lang/CharSequence;)V\ninvoke-virtual {v5, v6}, Landroid/text/SpannableString;->removeSpan(Ljava/lang/Object;)V\ninvoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v5\ninstance-of v1, v5, Landroid/text/SpannedString;\nconst/4 v2, 1\n' + eq('v1', 'v2', class + ' snapshots mutable Spanned')
		b += 'check-cast v5, Landroid/text/Spanned;\ninvoke-interface {v5, v6}, Landroid/text/Spanned;->getSpanStart(Ljava/lang/Object;)I\nmove-result v1\nconst/4 v2, 0\n' + eq('v1', 'v2', class + ' preserves span after source mutation')
		b += 'const/4 v1, 0\ninvoke-virtual {v0, v1}, ${widget}->setHint(Ljava/lang/CharSequence;)V\ninvoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v2\n' + same('v1', 'v2', class + ' null hint retained')
		b += set_hint('v0', '') + 'invoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v1\ninvoke-interface {v1}, Ljava/lang/CharSequence;->length()I\nmove-result v1\nconst/4 v2, 0\n' + eq('v1', 'v2', class + ' empty hint retained')
	}
	b += 'new-instance v0, Lorg/vinix/bootstrap/CountingTextView;\nconst v1, @NEUTRAL@\ninvoke-direct {v0, p0, v1}, Lorg/vinix/bootstrap/CountingTextView;-><init>(Landroid/content/Context;I)V\ninvoke-static {v0}, ${probe_class}->configure(${widget})V\nconst/4 v1, 0\niput v1, v0, Lorg/vinix/bootstrap/CountingTextView;->calls:I\niput v1, v0, Lorg/vinix/bootstrap/CountingTextView;->layouts:I\niput v1, v0, Lorg/vinix/bootstrap/CountingTextView;->invalidations:I\nconst v1, @HINT_STRING@\ninvoke-virtual {v0, v1}, ${widget}->setHint(I)V\niget v1, v0, Lorg/vinix/bootstrap/CountingTextView;->calls:I\nconst/4 v2, 1\n' + eq('v1', 'v2', 'resource hint uses virtual sequence overload once')
	b += 'iget-object v1, v0, Lorg/vinix/bootstrap/CountingTextView;->last:Ljava/lang/CharSequence;\ninvoke-interface {v1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v1\nconst-string v2, "Resource hint H"\ninvoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', 'resource hint resolves string')
	for field in ['layouts', 'invalidations'] {
		b += 'iget v1, v0, Lorg/vinix/bootstrap/CountingTextView;->${field}:I\nif-gtz v1, :${field}_ok\nconst/4 v2, 1\n' + eq('v1', 'v2', 'hint setter requests ' + field) + ':${field}_ok\n'
	}
	// Constructor XML has its own hint and color, independent of setters below.
	b += 'invoke-static {p0}, Landroid/view/LayoutInflater;->from(Landroid/content/Context;)Landroid/view/LayoutInflater;\nmove-result-object v1\nconst v2, @HINT_LAYOUT@\nconst/4 v3, 0\ninvoke-virtual {v1, v2, v3}, Landroid/view/LayoutInflater;->inflate(ILandroid/view/ViewGroup;)Landroid/view/View;\nmove-result-object v0\ncheck-cast v0, ${widget}\ninvoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v1\ninvoke-interface {v1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v1\nconst-string v2, "Resource hint H"\ninvoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', 'XML constructor hint')
	b += 'invoke-virtual {v0}, ${widget}->getCurrentHintTextColor()I\nmove-result v1\nconst v2, 0xffff00ff\n' + eq('v1', 'v2', 'XML constructor hint color')
	b += marker('APIS') + 'return-void'
	return method('private static apis(Landroid/content/Context;)V', b, 10)
}

fn pixel_probe() string {
	mut b := ''
	for class in ['TextView', 'EditText'] {
		b += create(class, 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\n' + set_hint('v0', 'HH HINT')
		b += ink('v0', '0xffff00ff', true, class + ' empty field paints hint') + 'move-object v7, v6\n' + ink('v0', '0xffff0000', false, class + ' hint uses hint color')
		b += set_text('v0', 'HH HINT') + ink('v0', '0xffff00ff', false, class + ' text hides hint') + ink('v0', '0xffff0000', true, class + ' entered text uses text color')
		b += 'const-string v3, "${class} hint and text share positions and glyphs"\ninvoke-static {v6, v7, v3}, ${probe_class}->compare([I[ILjava/lang/String;)V\n'
		b += set_text('v0', '') + ink('v0', '0xffff00ff', true, class + ' clearing text restores hint')
		b += 'const/4 v1, 0\ninvoke-virtual {v0, v1}, ${widget}->setHint(Ljava/lang/CharSequence;)V\n' + ink('v0', '0xffff00ff', false, class + ' null hides hint')
		b += 'invoke-static {v0}, ${probe_class}->raster(Landroid/view/View;)[I\nmove-result-object v7\n'
		b += set_hint('v0', '') + ink('v0', '0xffff00ff', false, class + ' empty hides hint')
		b += set_hint('v0', 'HH HINT') + 'const v1, 0x00ff00ff\ninvoke-virtual {v0, v1}, ${widget}->setHintTextColor(I)V\n' + ink('v0', '0xffff00ff', false, class + ' transparent hint color hides glyphs')
		if class == 'TextView' {
			b += ink('v0', '0x01000000', false, class + ' transparent hint color hides all ink')
		}
		// EditText always paints its underline; preserve every baseline pixel exactly.
		b += 'invoke-static {v0}, ${probe_class}->raster(Landroid/view/View;)[I\nmove-result-object v6\nconst-string v3, "${class} transparent hint matches entire null-hint bitmap"\ninvoke-static {v6, v7, v3}, ${probe_class}->sameRaster([I[ILjava/lang/String;)V\n'
	}
	// Multiline hint shares padding, gravity and alignment behavior with text.
	for gravity in [0x33, 0x11, 0x55] {
		b += create('TextView', 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${widget}->setSingleLine(Z)V\nconst/16 v1, ${gravity}\ninvoke-virtual {v0, v1}, ${widget}->setGravity(I)V\n' + set_hint('v0', 'H H H H H H H H H H H H H H H H H H H H')
		b += ink('v0', '0xffff00ff', true, 'multiline hint gravity ${gravity}') + 'move-object v7, v6\n'
		b += set_text('v0', 'H H H H H H H H H H H H H H H H H H H H') + ink('v0', '0xffff0000', true, 'multiline reference gravity ${gravity}')
		b += 'const-string v3, "multiline hint/text bounds gravity ${gravity}"\ninvoke-static {v6, v7, v3}, ${probe_class}->compare([I[ILjava/lang/String;)V\n'
	}
	b += marker('PIXELS') + 'return-void'
	return method('private static pixelsProbe(Landroid/content/Context;)V', b, 10)
}

fn color_probe() string {
	mut b := create('TextView', 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\n' + set_hint('v0', 'HH HINT')
	// Disabled first, then selected, then default, exercising live View states.
	b += 'const/4 v1, 3\nnew-array v5, v1, [[I\nconst/4 v1, 1\nnew-array v2, v1, [I\nconst/4 v3, 0\nconst v4, -0x101009e\naput v4, v2, v3\naput-object v2, v5, v3\nnew-array v2, v1, [I\nconst v4, 0x10100a1\naput v4, v2, v3\naput-object v2, v5, v1\nnew-array v2, v3, [I\nconst/4 v1, 2\naput-object v2, v5, v1\nconst/4 v1, 3\nnew-array v6, v1, [I\nconst/4 v1, 0\nconst v2, 0xff0000ff\naput v2, v6, v1\nconst/4 v1, 1\nconst v2, 0xff00ff00\naput v2, v6, v1\nconst/4 v1, 2\nconst v2, 0xffff00ff\naput v2, v6, v1\nnew-instance v8, Landroid/content/res/ColorStateList;\ninvoke-direct {v8, v5, v6}, Landroid/content/res/ColorStateList;-><init>([[I[I)V\ninvoke-virtual {v0, v8}, ${widget}->setHintTextColor(Landroid/content/res/ColorStateList;)V\ninvoke-virtual {v0}, ${widget}->getHintTextColors()Landroid/content/res/ColorStateList;\nmove-result-object v1\n' + same('v1', 'v8', 'hint ColorStateList retained identity')
	for i, state in ['normal', 'selected', 'disabled', 'restored'] {
		color := ['0xffff00ff', '0xff00ff00', '0xff0000ff', '0xffff00ff'][i]
		if state == 'selected' {
			b += 'const/4 v1, 1\ninvoke-virtual {v0, v1}, Landroid/view/View;->setSelected(Z)V\n'
		} else if state == 'disabled' {
			b += 'const/4 v1, 0\ninvoke-virtual {v0, v1}, Landroid/view/View;->setEnabled(Z)V\n'
		} else if state == 'restored' {
			b += 'const/4 v1, 1\ninvoke-virtual {v0, v1}, Landroid/view/View;->setEnabled(Z)V\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, Landroid/view/View;->setSelected(Z)V\n'
		}
		b += 'invoke-virtual {v0}, ${widget}->getCurrentHintTextColor()I\nmove-result v1\nconst v2, ${color}\n' + eq('v1', 'v2', state + ' hint color query') + ink('v0', color, true, state + ' hint pixels')
	}
	b += 'const v1, 0xff336699\ninvoke-virtual {v0, v1}, ${widget}->setHintTextColor(I)V\ninvoke-virtual {v0}, ${widget}->getCurrentHintTextColor()I\nmove-result v1\nconst v2, 0xff336699\n' + eq('v1', 'v2', 'scalar hint color replaces stateful list') + ink('v0', '0xff336699', true, 'replacement scalar hint pixels')
	b += 'const/4 v1, 0\ninvoke-virtual {v0, v1}, ${widget}->setHintTextColor(Landroid/content/res/ColorStateList;)V\ninvoke-virtual {v0}, ${widget}->getHintTextColors()Landroid/content/res/ColorStateList;\nmove-result-object v2\n' + same('v1', 'v2', 'null hint colors retained')
	b += 'invoke-virtual {v0}, ${widget}->getCurrentHintTextColor()I\nmove-result v1\ninvoke-virtual {v0}, ${widget}->getCurrentTextColor()I\nmove-result v2\n' + eq('v1', 'v2', 'null hint colors fall back to text color') + ink('v0', '0xffff0000', true, 'null hint colors use text color pixels')
	b += 'const v1, 0xff123456\ninvoke-virtual {v0, v1}, ${widget}->setTextColor(I)V\ninvoke-virtual {v0}, ${widget}->getCurrentHintTextColor()I\nmove-result v1\nconst v2, 0xff123456\n' + eq('v1', 'v2', 'null hint color follows text color changes') + ink('v0', '0xff123456', true, 'updated text color drives fallback hint pixels')
	// A missing default state must resolve transparent, never list.getDefaultColor().
	b += 'const/4 v1, 1\nnew-array v5, v1, [[I\nnew-array v2, v1, [I\nconst/4 v3, 0\nconst v4, 0x10100a1\naput v4, v2, v3\naput-object v2, v5, v3\nnew-array v6, v1, [I\nconst v2, 0xffabcdef\naput v2, v6, v3\nnew-instance v8, Landroid/content/res/ColorStateList;\ninvoke-direct {v8, v5, v6}, Landroid/content/res/ColorStateList;-><init>([[I[I)V\ninvoke-virtual {v0, v8}, ${widget}->setHintTextColor(Landroid/content/res/ColorStateList;)V\ninvoke-virtual {v0}, ${widget}->getCurrentHintTextColor()I\nmove-result v1\nconst/4 v2, 0\n' + eq('v1', 'v2', 'unmatched hint state resolves transparent zero') + ink('v0', '0x01000000', false, 'unmatched hint state draws no ink')
	b += 'const/4 v1, 1\ninvoke-virtual {v0, v1}, Landroid/view/View;->setSelected(Z)V\ninvoke-virtual {v0}, ${widget}->getCurrentHintTextColor()I\nmove-result v1\nconst v2, 0xffabcdef\n' + eq('v1', 'v2', 'selected-only hint state matches selected view') + ink('v0', '0xffabcdef', true, 'selected-only hint state draws selected color')
	b += marker('COLORS') + 'return-void'
	return method('private static colors(Landroid/content/Context;)V', b, 10)
}

fn measurement_probe() string {
	mut b := ''
	for class in ['TextView', 'EditText'] {
		b += create(class, 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\n' + set_hint('v0', 'HH HINT LONG ENOUGH TO EXCEED EDIT MINIMUM') + 'move-object v8, v0\n'
		b += create(class, 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\n' + set_text('v0', 'HH HINT LONG ENOUGH TO EXCEED EDIT MINIMUM') + 'move-object v5, v0\nmove-object v0, v8\n'
		for phase in ['empty', 'short text'] {
			if phase == 'short text' { b += set_text('v0', 'H') }
			b += 'const/4 v1, 0\ninvoke-virtual {v0, v1, v1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v5, v1, v1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v0}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v1\ninvoke-virtual {v5}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v2\n' + eq('v1', 'v2', class + ' hint reserves width with ' + phase)
		}
	}
	b += create('TextView', 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${widget}->setSingleLine(Z)V\n' + set_hint('v0', 'H H H H H H H H H H H H H H H H H H H H') + 'move-object v8, v0\n'
	b += create('TextView', 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${widget}->setSingleLine(Z)V\n' + set_text('v0', 'H H H H H H H H H H H H H H H H H H H H') + 'move-object v5, v0\nmove-object v0, v8\nconst v1, 0x80000060\nconst/4 v2, 0\ninvoke-virtual {v0, v1, v2}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v5, v1, v2}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v0}, Landroid/view/View;->getMeasuredHeight()I\nmove-result v1\ninvoke-virtual {v5}, Landroid/view/View;->getMeasuredHeight()I\nmove-result v2\n' + eq('v1', 'v2', 'multiline empty hint contributes measured height')
	b += marker('MEASURE') + 'return-void'
	return method('private static measureProbe(Landroid/content/Context;)V', b, 10)
}

fn cursor_probe() string {
	mut b := create('EditText', 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\n' + set_hint('v0', 'HH HINT')
	b += 'const/4 v1, 1\ninvoke-virtual {v0, v1}, Landroid/view/View;->setFocusable(Z)V\ninvoke-virtual {v0}, Landroid/view/View;->requestFocus()Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', 'editable requestFocus succeeds')
	b += ink('v0', '0xffff00ff', true, 'focused empty field still paints hint') + ink('v0', '0xffff0000', true, 'focused empty field has text-color cursor')
	b += 'const/4 v1, 1\naget v2, v6, v1\nconst/16 v3, 15\nif-le v2, v3, :cursor_ok\n' + eq('v2', 'v3', 'empty cursor remains at start rather than after hint') + ':cursor_ok\n'
	// Text input moves the cursor; clearing brings it back and restores the hint.
	b += set_text('v0', 'HH HINT') + ink('v0', '0xffff00ff', false, 'focused entered text hides hint')
	b += set_text('v0', '') + ink('v0', '0xffff00ff', true, 'focused clearing restores hint') + ink('v0', '0xffff0000', true, 'cleared field cursor remains visible')
	b += 'const/4 v1, 1\naget v2, v6, v1\nconst/16 v3, 15\nif-le v2, v3, :cleared_ok\n' + eq('v2', 'v3', 'cleared cursor returns to start') + ':cleared_ok\n'
	b += marker('CURSOR') + 'return-void'
	return method('private static cursor(Landroid/content/Context;)V', b, 10)
}

fn ripple_probe() string {
	ripple := 'Landroid/graphics/drawable/RippleDrawable;'
	child := 'Lorg/vinix/bootstrap/RadiusRipple;'
	callback := 'Lorg/vinix/bootstrap/RippleCallback;'
	mut b := 'const v1, 0xff0000ff\ninvoke-static {v1}, Landroid/content/res/ColorStateList;->valueOf(I)Landroid/content/res/ColorStateList;\nmove-result-object v8\nnew-instance v0, ${ripple}\nconst/4 v1, 0\ninvoke-direct {v0, v8, v1, v1}, ${ripple}-><init>(Landroid/content/res/ColorStateList;Landroid/graphics/drawable/Drawable;Landroid/graphics/drawable/Drawable;)V\nnew-instance v5, ${child}\ninvoke-direct {v5, v8}, ${child}-><init>(Landroid/content/res/ColorStateList;)V\ninvoke-virtual {v0}, ${ripple}->getRadius()I\nmove-result v1\nconst/4 v2, -1\n' + eq('v1', 'v2', 'ripple default radius is automatic')
	b += 'invoke-virtual {v5}, ${child}->getRadius()I\nmove-result v1\nconst/4 v2, -1\n' + eq('v1', 'v2', 'subclass inherits automatic radius')
	b += 'sget v1, ${ripple}->RADIUS_AUTO:I\nconst/4 v2, -1\n' + eq('v1', 'v2', 'ripple automatic radius constant')
	b += 'new-instance v7, ${callback}\ninvoke-direct {v7}, ${callback}-><init>()V\ninvoke-virtual {v0, v7}, Landroid/graphics/drawable/Drawable;->setCallback(Landroid/graphics/drawable/Drawable$Callback;)V\n'
	for radius in [0, 23, -1, -1] {
		b += 'const/16 v1, ${radius}\ninvoke-virtual {v0, v1}, ${ripple}->setRadius(I)V\ninvoke-virtual {v0}, ${ripple}->getRadius()I\nmove-result v1\nconst/16 v2, ${radius}\n' + eq('v1', 'v2', 'explicit ripple radius ${radius}')
	}
	b += 'iget v1, v7, ${callback}->count:I\nconst/4 v2, 4\n' + eq('v1', 'v2', 'radius setter invalidates even for unchanged value')
	b += 'iget-object v1, v7, ${callback}->last:Landroid/graphics/drawable/Drawable;\n' + same('v1', 'v0', 'radius invalidation identifies changed drawable')
	b += 'invoke-virtual {v5}, ${child}->getRadius()I\nmove-result v1\nconst/4 v2, -1\n' + eq('v1', 'v2', 'independent ripple keeps automatic radius')
	b += 'const/16 v1, 42\ninvoke-virtual {v5, v1}, ${child}->setRadius(I)V\ninvoke-virtual {v5}, ${child}->getRadius()I\nmove-result v1\nconst/16 v2, 42\n' + eq('v1', 'v2', 'subclass inherits radius setter and getter')
	b += 'invoke-virtual {v0}, ${ripple}->getRadius()I\nmove-result v1\nconst/4 v2, -1\n' + eq('v1', 'v2', 'subclass mutation leaves first ripple unchanged')
	b += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-RIPPLE-RADIUS-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	return method('private static rippleRadius()V', b, 10)
}

fn ripple_support() string {
	return '.class public Lorg/vinix/bootstrap/RadiusRipple;\n.super Landroid/graphics/drawable/RippleDrawable;\n' + method('public constructor <init>(Landroid/content/res/ColorStateList;)V', 'const/4 v0, 0\ninvoke-direct {p0, p1, v0, v0}, Landroid/graphics/drawable/RippleDrawable;-><init>(Landroid/content/res/ColorStateList;Landroid/graphics/drawable/Drawable;Landroid/graphics/drawable/Drawable;)V\nreturn-void', 1)
}

fn ripple_callback() string {
	mut s := '.class public Lorg/vinix/bootstrap/RippleCallback;\n.super Ljava/lang/Object;\n.implements Landroid/graphics/drawable/Drawable$Callback;\n.field public count:I\n.field public last:Landroid/graphics/drawable/Drawable;\n'
	s += method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void', 0)
	s += method('public invalidateDrawable(Landroid/graphics/drawable/Drawable;)V', 'iget v0, p0, Lorg/vinix/bootstrap/RippleCallback;->count:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/RippleCallback;->count:I\niput-object p1, p0, Lorg/vinix/bootstrap/RippleCallback;->last:Landroid/graphics/drawable/Drawable;\nreturn-void', 1)
	s += method('public scheduleDrawable(Landroid/graphics/drawable/Drawable;Ljava/lang/Runnable;J)V', 'return-void', 0)
	s += method('public unscheduleDrawable(Landroid/graphics/drawable/Drawable;Ljava/lang/Runnable;)V', 'return-void', 0)
	return s
}

fn probe() string {
	mut s := '.class public ${probe_class}\n.super Ljava/lang/Object;\n' + helpers()
	// Recognize only the known baseline stubs; the changed runner requires every new marker.
	mut run := 'invoke-static {}, ${probe_class}->traceAbsent()V\n' + create('TextView', 'v0')
	run += 'invoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v1\nif-eqz v1, :changed\ninvoke-interface {v1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v1\nconst-string v2, "HINT"\ninvoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', 'known TextView baseline hint stub')
	run += create('EditText', 'v0') + 'invoke-static {v0}, ${probe_class}->configure(${widget})V\n' + set_hint('v0', 'HH HINT') + 'invoke-virtual {v0}, ${widget}->getHint()Ljava/lang/CharSequence;\nmove-result-object v1\ninvoke-interface {v1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v1\nconst-string v2, "HH HINT"\ninvoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', 'baseline EditText stored hint') + ink('v0', '0xffff00ff', false, 'baseline stored hint is not drawn')
	run += marker('EXPECTED-STUB') + 'const/4 v0, 0\nreturn v0\n:changed\n'
	for name in ['apis', 'pixelsProbe', 'colors', 'measureProbe', 'cursor'] {
		run += 'invoke-static {p0}, ${probe_class}->${name}(Landroid/content/Context;)V\n'
	}
	run += 'invoke-static {}, ${probe_class}->rippleRadius()V\n'
	run += 'const/4 v0, 1\nreturn v0'
	s += method('public static run(Landroid/content/Context;)Z', run, 10)
	return s + api_probe() + pixel_probe() + color_probe() + measurement_probe() + cursor_probe() + ripple_probe()
}

fn counting_view() string {
	mut s := '.class public Lorg/vinix/bootstrap/CountingTextView;\n.super ${widget}\n.field public calls:I\n.field public layouts:I\n.field public invalidations:I\n.field public last:Ljava/lang/CharSequence;\n'
	s += method('public constructor <init>(Landroid/content/Context;I)V', 'const/4 v0, 0\ninvoke-direct {p0, p1, v0, v0, p2}, ${widget}-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\nreturn-void', 1)
	s += method('public setHint(Ljava/lang/CharSequence;)V', 'iget v0, p0, Lorg/vinix/bootstrap/CountingTextView;->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/CountingTextView;->calls:I\niput-object p1, p0, Lorg/vinix/bootstrap/CountingTextView;->last:Ljava/lang/CharSequence;\ninvoke-super {p0, p1}, ${widget}->setHint(Ljava/lang/CharSequence;)V\nreturn-void', 1)
	for name, field in {'requestLayout': 'layouts', 'invalidate': 'invalidations'} {
		s += method('public ${name}()V', 'iget v0, p0, Lorg/vinix/bootstrap/CountingTextView;->${field}:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/CountingTextView;->${field}:I\ninvoke-super {p0}, Landroid/view/View;->${name}()V\nreturn-void', 1)
	}
	return s
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, ${widget}\ninvoke-direct {v0, p0}, ${widget}-><init>(Landroid/content/Context;)V\nconst-string v1, "Text hint JNI fixture"\ninvoke-virtual {v0, v1}, ${widget}->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\ninvoke-static {p0}, ${probe_class}->run(Landroid/content/Context;)Z\nmove-result v0\nif-eqz v0, :ready\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-TEXT-HINT-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n:ready\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2)
}

fn file_hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins { assert file_hash(path)! == pin, path }
	started := time.utc().str()
	r := os.exec(args)
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({'argv': json2.Any(args),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(r.exit_code), 'input_sha256': json2.decode[json2.Any](json2.encode(pins))!,
		'generator_sha256': json2.Any(file_hash(os.executable())!)}, prettify: true) + '\n')!
	for path, pin in pins { assert file_hash(path)! == pin, path }
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/values')!
	os.mkdir_all(out + '/res/layout')!
	os.write_file(out + '/res/values/values.xml', '<resources><style name="NeutralText" parent="android:style/Widget"/><string name="fixture_hint">Resource hint H</string></resources>')!
	os.write_file(out + '/res/layout/hint.xml', '<TextView xmlns:android="http://schemas.android.com/apk/res/android" style="@style/NeutralText" android:layout_width="wrap_content" android:layout_height="wrap_content" android:hint="@string/fixture_hint" android:textColorHint="#ffff00ff"/>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Text hint fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/CountingTextView.smali', counting_view())!
	os.write_file(root + '/RadiusRipple.smali', ripple_support())!
	os.write_file(root + '/RippleCallback.smali', ripple_callback())!
	tools := os.getenv('TEXT_HINT_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' { os.abs_path('build/android-native-ws/aapt2') } else { tools + '/aapt2' }
	signer := if tools == '' { os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar') } else { tools + '/apksigner.jar' }
	framework := if tools == '' { '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk' } else { tools + '/framework-res.apk' }
	smali := if tools == '' { os.abs_path('build/android-framework/tools') } else { tools + '/smali' }
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = file_hash(path)! }
	for name in os.ls(smali)! { if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! } }
	assert pins.len > 6
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '--output-text-symbols', out + '/R.txt', '-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	mut ids := map[string]string{}
	for line in os.read_lines(out + '/R.txt')! {
		parts := line.fields()
		if parts.len == 4 && parts[0] == 'int' { ids[parts[1] + '/' + parts[2]] = parts[3] }
	}
	os.write_file(root + '/HintProbe.smali', probe().replace('@NEUTRAL@', ids['style/NeutralText']!).replace('@HINT_STRING@', ids['string/fixture_hint']!).replace('@HINT_LAYOUT@', ids['layout/hint']!))!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Text hint fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('TEXT-HINT-APK ' + file_hash(out + '/probe.apk')!)
}
