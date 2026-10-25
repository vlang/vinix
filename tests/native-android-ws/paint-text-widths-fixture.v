// SPDX-License-Identifier: GPL-2.0-or-later
// One signed APK exercises the missing Maps descriptor and all public overloads.
module main

import crypto.sha256
import json2
import os
import time

const probe = 'Lorg/vinix/bootstrap/PaintTextWidthsProbe;'
const paint = 'Landroid/graphics/Paint;'
const sequence = 'Lorg/vinix/bootstrap/WidthSequence;'
const sentinel = '0xc2c60000' // -99.0f, outside the valid advance domain.

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "BOOTSTRAP-PAINT-TEXT-WIDTHS-${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn equal(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${actual}, ${expected}, v9}, ${probe}->equal(IILjava/lang/String;)V\n'
}

fn near(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${actual}, ${expected}, v9}, ${probe}->near(FFLjava/lang/String;)V\n'
}

fn helpers() string {
	mut s := method('private static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 1)
	s += method('private static equal(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 0)
	s += method('private static near(FFLjava/lang/String;)V', '
sub-float v0, p0, p1
invoke-static {v0}, Ljava/lang/Math;->abs(F)F
move-result v0
const v1, 0x3b03126f
cmpg-float v0, v0, v1
if-lez v0, :ok
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 2)
	s += method('private static positive(FLjava/lang/String;)V', '
const/4 v0, 0
cmpl-float v0, p0, v0
if-gtz v0, :ok
invoke-static {p1}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 1)
	s += method('private static output(I)[F', '
new-array v0, p0, [F
const/4 v1, 0
const v2, ${sentinel}
:next
if-ge v1, p0, :done
aput v2, v0, v1
add-int/lit8 v1, v1, 1
goto :next
:done
return-object v0', 3)
	s += method('private static untouched([FI)V', '
array-length v0, p0
const v1, ${sentinel}
:next
if-ge p1, v0, :done
aget v2, p0, p1
cmpl-float v2, v2, v1
if-eqz v2, :good
const-string v2, "output beyond count or after failure was modified"
invoke-static {v2}, ${probe}->fail(Ljava/lang/String;)V
:good
add-int/lit8 p1, p1, 1
goto :next
:done
return-void', 3)
	s += method('private static prefix([F[FI)V', '
const/4 v0, 0
:next
if-ge v0, p2, :done
aget v1, p0, v0
aget v2, p1, v0
const-string v3, "overload/repeated advances differ"
invoke-static {v1, v2, v3}, ${probe}->near(FFLjava/lang/String;)V
add-int/lit8 v0, v0, 1
goto :next
:done
return-void', 4)
	// This compares the sum of per-UTF16-unit advances against the existing
	// measureText backend. Its public API currently rounds the total upward.
	s += method('private static measured(${paint}Ljava/lang/String;[F)V', '
const/4 v0, 0
const/4 v1, 0
invoke-virtual {p1}, Ljava/lang/String;->length()I
move-result v2
:next
if-ge v0, v2, :sum_done
aget v3, p2, v0
add-float/2addr v1, v3
add-int/lit8 v0, v0, 1
goto :next
:sum_done
float-to-double v0, v1
invoke-static {v0, v1}, Ljava/lang/Math;->ceil(D)D
move-result-wide v0
double-to-float v0, v0
invoke-virtual {p0, p1}, ${paint}->measureText(Ljava/lang/String;)F
move-result v1
const-string v2, "ceil(sum widths) differs from measureText"
invoke-static {v0, v1, v2}, ${probe}->near(FFLjava/lang/String;)V
return-void', 4)
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
const-string v0, "trace variables must be absent"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:good
' + marker('TRACE-ENV-ABSENT-PASS') + 'return-void', 3)
	return s
}

// All generated calls use these four real public descriptors. Keeping this
// selector in V makes both the success and failure matrices exercise each one.
fn call_widths(kind int, receiver string, text string, start string, end string, output string) string {
	return match kind {
		0 {
			'invoke-virtual {${receiver}, ${text}, ${output}}, ${paint}->getTextWidths(Ljava/lang/String;[F)I\n'
		}
		1 {
			'invoke-virtual {${receiver}, ${text}, ${start}, ${end}, ${output}}, ${paint}->getTextWidths(Ljava/lang/String;II[F)I\n'
		}
		2 {
			'invoke-virtual {${receiver}, ${text}, ${start}, ${end}, ${output}}, ${paint}->getTextWidths([CII[F)I\n'
		}
		else {
			'invoke-virtual {${receiver}, ${text}, ${start}, ${end}, ${output}}, ${paint}->getTextWidths(Ljava/lang/CharSequence;II[F)I\n'
		}
	}
}

fn text_value(kind int, value string, register string) string {
	mut s := 'const-string ${register}, "${value}"\n'
	if kind == 2 {
		s += 'invoke-virtual {${register}}, Ljava/lang/String;->toCharArray()[C\nmove-result-object ${register}\n'
	} else if kind == 3 {
		s += 'new-instance v8, ${sequence}\ninvoke-direct {v8, ${register}}, ${sequence}-><init>(Ljava/lang/String;)V\nmove-object ${register}, v8\n'
	}
	return s
}

fn basic_probe() string {
	mut s := '
new-instance v6, ${paint}
invoke-direct {v6}, ${paint}-><init>()V
const/high16 v0, 0x41a00000
invoke-virtual {v6, v0}, ${paint}->setTextSize(F)V
const-string v7, "Wi W"
const/4 v0, 7
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v8
' + marker('CALL') + '
# Keep this exact Maps descriptor first: old framework must fail here.
invoke-virtual {v6, v7, v8}, ${paint}->getTextWidths(Ljava/lang/String;[F)I
move-result v0
const/4 v1, 4
' + equal('v0', 'v1', 'String convenience returns UTF16 count') + '
const/4 v0, 4
invoke-static {v8, v0}, ${probe}->untouched([FI)V
const/4 v0, 0
aget v1, v8, v0
const-string v9, "W advance is positive"
invoke-static {v1, v9}, ${probe}->positive(FLjava/lang/String;)V
const/4 v0, 1
aget v2, v8, v0
const-string v9, "i advance is positive"
invoke-static {v2, v9}, ${probe}->positive(FLjava/lang/String;)V
cmpl-float v0, v1, v2
if-gtz v0, :proportional
const-string v0, "default font must have proportional W and i advances"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:proportional
const/4 v0, 2
aget v2, v8, v0
const-string v9, "space advance is positive"
invoke-static {v2, v9}, ${probe}->positive(FLjava/lang/String;)V
const/4 v0, 3
aget v2, v8, v0
' + near('v1', 'v2', 'repeated W has stable advance') + '
invoke-static {v6, v7, v8}, ${probe}->measured(${paint}Ljava/lang/String;[F)V
const/4 v5, 0
:repeat
const/4 v0, 7
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v4
invoke-virtual {v6, v7, v4}, ${paint}->getTextWidths(Ljava/lang/String;[F)I
move-result v0
const/4 v1, 4
' + equal('v0', 'v1', 'repeat count') + '
invoke-static {v8, v4, v1}, ${probe}->prefix([F[FI)V
invoke-static {v4, v1}, ${probe}->untouched([FI)V
add-int/lit8 v5, v5, 1
const/16 v0, 16
if-lt v5, v0, :repeat
'
	for kind in 1 .. 4 {
		s += text_value(kind, 'xWi Wx', 'v2') + '
const/4 v0, 7
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v4
const/4 v0, 1
const/4 v1, ${if kind == 2 { 4 } else { 5 }}
' + call_widths(kind, 'v6', 'v2', 'v0', 'v1', 'v4') + '
move-result v0
const/4 v1, 4
' + equal('v0', 'v1', 'range overload ${kind} UTF16 count') + '
invoke-static {v8, v4, v1}, ${probe}->prefix([F[FI)V
invoke-static {v4, v1}, ${probe}->untouched([FI)V
'
	}
	s += marker('OVERLOADS-PASS') + 'return-void'
	// text_value uses v8 for CharSequence construction; preserve the reference
	// output in v10 while that helper is used, then restore for comparison.
	s = s.replace(text_value(3, 'xWi Wx', 'v2'), 'move-object v10, v8\n' +
		text_value(3, 'xWi Wx', 'v2') + 'move-object v8, v10\n')
	return method('private static basics()V', s, 11)
}

fn unicode_probe() string {
	mut s := '
new-instance v6, ${paint}
invoke-direct {v6}, ${paint}-><init>()V
const/high16 v0, 0x41c00000
invoke-virtual {v6, v0}, ${paint}->setTextSize(F)V
const-string v7, "A😀B"
const/4 v0, 7
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v8
invoke-virtual {v6, v7, v8}, ${paint}->getTextWidths(Ljava/lang/String;[F)I
move-result v0
const/4 v1, 4
' + equal('v0', 'v1', 'supplementary text count is UTF16 units') + '
const/4 v0, 1
aget v1, v8, v0
const-string v9, "supplementary leading surrogate owns the advance"
invoke-static {v1, v9}, ${probe}->positive(FLjava/lang/String;)V
const/4 v0, 2
aget v1, v8, v0
const/4 v2, 0
' + near('v1', 'v2', 'supplementary trailing surrogate has zero advance') + '
const/4 v0, 4
invoke-static {v8, v0}, ${probe}->untouched([FI)V
invoke-static {v6, v7, v8}, ${probe}->measured(${paint}Ljava/lang/String;[F)V
'
	for kind in 1 .. 4 {
		s += text_value(kind, 'xA😀Bx', 'v2') + '
const/4 v0, 7
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v4
const/4 v0, 1
const/4 v1, ${if kind == 2 { 4 } else { 5 }}
' + call_widths(kind, 'v6', 'v2', 'v0', 'v1', 'v4') + '
move-result v0
const/4 v1, 4
' + equal('v0', 'v1', 'supplementary overload ${kind} count') + '
invoke-static {v8, v4, v1}, ${probe}->prefix([F[FI)V
invoke-static {v4, v1}, ${probe}->untouched([FI)V
'
	}
	s = s.replace(text_value(3, 'xA😀Bx', 'v2'), 'move-object v10, v8\n' +
		text_value(3, 'xA😀Bx', 'v2') + 'move-object v8, v10\n')
	return method('private static unicode()V', s + marker('UTF16-PASS') + 'return-void', 11)
}

fn boundary_probe() string {
	mut s := '
new-instance v6, ${paint}
invoke-direct {v6}, ${paint}-><init>()V
const/high16 v0, 0x41c00000
invoke-virtual {v6, v0}, ${paint}->setTextSize(F)V
const-string v7, "�"
const/4 v0, 4
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v8
invoke-virtual {v6, v7, v8}, ${paint}->getTextWidths(Ljava/lang/String;[F)I
move-result v0
const/4 v1, 1
' + equal('v0', 'v1', 'replacement character count') + '
invoke-static {v8, v1}, ${probe}->untouched([FI)V
const/4 v0, 0
aget v1, v8, v0
const-string v9, "replacement character advance is positive"
invoke-static {v1, v9}, ${probe}->positive(FLjava/lang/String;)V
'
	// The decoder must not read either half of a supplementary pair outside
	// the selected UTF16 range. Each isolated unit becomes one replacement.
	for kind in 1 .. 4 {
		for start in [1, 2] {
			s += 'move-object v10, v8\n' + text_value(kind, 'x😀y', 'v2') +
				'move-object v8, v10\n' + '
const/4 v0, 4
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v4
const/4 v0, ${start}
const/4 v1, ${if kind == 2 { 1 } else { start + 1 }}
' + call_widths(kind, 'v6', 'v2', 'v0', 'v1', 'v4') + '
move-result v0
const/4 v1, 1
' + equal('v0', 'v1', 'isolated surrogate overload ${kind} start ${start} count') + '
invoke-static {v8, v4, v1}, ${probe}->prefix([F[FI)V
invoke-static {v4, v1}, ${probe}->untouched([FI)V
'
		}
	}
	return method('private static boundaries()V', s + marker('BOUNDARIES-PASS') + 'return-void', 11)
}

fn metrics_probe() string {
	return method('private static metrics()V', '
new-instance v6, ${paint}
invoke-direct {v6}, ${paint}-><init>()V
const-string v7, "Wi W"
const/high16 v0, 0x41a00000
invoke-virtual {v6, v0}, ${paint}->setTextSize(F)V
const/4 v0, 4
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v8
invoke-virtual {v6, v7, v8}, ${paint}->getTextWidths(Ljava/lang/String;[F)I
const/high16 v0, 0x42200000
invoke-virtual {v6, v0}, ${paint}->setTextSize(F)V
const/4 v0, 4
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v4
invoke-virtual {v6, v7, v4}, ${paint}->getTextWidths(Ljava/lang/String;[F)I
const/4 v3, 0
:size_next
const/4 v0, 4
if-ge v3, v0, :size_done
aget v0, v8, v3
const/high16 v1, 0x40000000
mul-float/2addr v0, v1
aget v1, v4, v3
' + near('v1', 'v0', 'size change scales each advance') + '
add-int/lit8 v3, v3, 1
goto :size_next
:size_done
invoke-static {v6, v7, v4}, ${probe}->measured(${paint}Ljava/lang/String;[F)V
sget-object v0, Landroid/graphics/Typeface;->MONOSPACE:Landroid/graphics/Typeface;
invoke-virtual {v6, v0}, ${paint}->setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;
invoke-virtual {v6, v7, v4}, ${paint}->getTextWidths(Ljava/lang/String;[F)I
const/4 v0, 0
aget v1, v4, v0
const-string v9, "monospace advance is positive"
invoke-static {v1, v9}, ${probe}->positive(FLjava/lang/String;)V
const/4 v3, 1
:font_next
const/4 v0, 4
if-ge v3, v0, :font_done
aget v2, v4, v3
' + near('v2', 'v1', 'typeface change uses monospace metrics') + '
add-int/lit8 v3, v3, 1
goto :font_next
:font_done
invoke-static {v6, v7, v4}, ${probe}->measured(${paint}Ljava/lang/String;[F)V
' + marker('METRICS-PASS') + 'return-void', 10)
}

fn zero_probe() string {
	mut s := 'new-instance v6, ${paint}\ninvoke-direct {v6}, ${paint}-><init>()V\n'
	for kind in 0 .. 4 {
		for nonempty in [false, true] {
			if kind == 0 && nonempty { continue }
			s += text_value(kind, if nonempty { 'xWi Wx' } else { '' }, 'v2') + '
const/4 v0, 3
invoke-static {v0}, ${probe}->output(I)[F
move-result-object v4
const/4 v0, ${if nonempty { 2 } else { 0 }}
const/4 v1, ${if nonempty && kind != 2 { 2 } else { 0 }}
' + call_widths(kind, 'v6', 'v2', 'v0', 'v1', 'v4') + '
move-result v0
const/4 v1, 0
' + equal('v0', 'v1', 'empty/range-zero overload ${kind}') + '
invoke-static {v4, v1}, ${probe}->untouched([FI)V
'
		}
	}
	return method('private static zero()V', s + marker('ZERO-PASS') + 'return-void', 10)
}

struct FailureCase {
	name        string
	start       int
	end         int
	length      int = 7
	null_text   bool
	null_widths bool
	class       string
}

fn failure_cases(kind int) []FailureCase {
	mut cases := [
		FailureCase{
			name:      'null text'
			null_text: true
			class:     if kind == 0 {
				'NullPointerException'
			} else {
				'IllegalArgumentException'
			}
		},
		FailureCase{ name: 'null widths', end: 5, null_widths: true, class: 'NullPointerException' },
		FailureCase{
			name:   'short output'
			start:  if kind == 0 { 0 } else { 1 }
			end:    if kind == 2 {
				3
			} else if kind == 0 {
				5
			} else {
				4
			}
			length: 1
			class:  'ArrayIndexOutOfBoundsException'
		},
		FailureCase{
			name:        'null text wins over null widths'
			null_text:   true
			null_widths: true
			class:       if kind == 0 {
				'NullPointerException'
			} else {
				'IllegalArgumentException'
			}
		},
	]
	if kind != 0 {
		range_class := if kind == 2 {
			'ArrayIndexOutOfBoundsException'
		} else {
			'IndexOutOfBoundsException'
		}
		cases << FailureCase{ name: 'negative start', start: -1, end: 1, class: range_class }
		cases << FailureCase{ name: 'negative end or count', end: -1, class: range_class }
		cases << FailureCase{ name: 'out of bounds', start: 4, end: if kind == 2 { 2 } else { 6 }, class: range_class }
		cases << FailureCase{
			name:  'overflow'
			start: 0x7fffffff
			end:   if kind == 2 {
				0x7fffffff
			} else {
				5
			}
			class: range_class
		}
		cases << FailureCase{
			name:        'zero range null widths'
			null_widths: true
			start:       2
			end:         if kind == 2 {
				0
			} else {
				2
			}
			class:       'NullPointerException'
		}
		if kind != 2 {
			cases << FailureCase{ name: 'reversed range', start: 4, end: 2, class: range_class }
		}
	}
	return cases
}

fn validation_probe() string {
	mut methods := ''
	mut run := ''
	for kind in 0 .. 4 {
		for index, test in failure_cases(kind) {
			name := 'failure${kind}_${index}'
			run += 'invoke-static {}, ${probe}->${name}()V\n'
			mut s := 'new-instance v6, ${paint}\ninvoke-direct {v6}, ${paint}-><init>()V\n'
			s += text_value(kind, 'xWi W', 'v2')
			if test.null_text { s += 'const/4 v2, 0\n' }
			if test.null_widths {
				s += 'const/4 v4, 0\n'
			} else {
				s += 'const v0, ${test.length}\ninvoke-static {v0}, ${probe}->output(I)[F\nmove-result-object v4\n'
			}
			s += 'const v0, ${test.start}\nconst v1, ${test.end}\n:try_start\n' +
				call_widths(kind, 'v6', 'v2', 'v0', 'v1', 'v4') + '
:try_end
const-string v0, "overload ${kind}: ${test.name} did not throw"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
goto :done
.catch Ljava/lang/Throwable; {:try_start .. :try_end} :caught
:caught
move-exception v5
invoke-virtual {v5}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
const-class v1, Ljava/lang/${test.class};
if-eq v0, v1, :expected
throw v5
:expected
'
			if !test.null_widths {
				s += 'const/4 v0, 0\ninvoke-static {v4, v0}, ${probe}->untouched([FI)V\n'
			}
			methods += method('private static ${name}()V', s + ':done\nreturn-void', 10)
		}
	}
	return methods + method('private static validation()V', run + marker('VALIDATION-PASS') + 'return-void', 2)
}

fn probe_class() string {
	return '.class public ${probe}\n.super Ljava/lang/Object;\n' + helpers() +
		basic_probe() + unicode_probe() + boundary_probe() + metrics_probe() + zero_probe() + validation_probe() +
		method('public static run()V', 'invoke-static {}, ${probe}->traceAbsent()V\n' +
			'invoke-static {}, ${probe}->basics()V\ninvoke-static {}, ${probe}->unicode()V\n' +
			'invoke-static {}, ${probe}->boundaries()V\n' +
			'invoke-static {}, ${probe}->metrics()V\ninvoke-static {}, ${probe}->zero()V\n' +
			'invoke-static {}, ${probe}->validation()V\n' + marker('PASS') + 'return-void', 2)
}

// A distinct toString value catches implementations that measure toString()
// instead of the requested UTF16 range exposed by length()/charAt().
fn sequence_class() string {
	return '.class public ${sequence}\n.super Ljava/lang/Object;\n.implements Ljava/lang/CharSequence;\n.field private value:Ljava/lang/String;\n' +
		method('public constructor <init>(Ljava/lang/String;)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${sequence}->value:Ljava/lang/String;\nreturn-void', 0) +
		method('public length()I', 'iget-object v0, p0, ${sequence}->value:Ljava/lang/String;\ninvoke-virtual {v0}, Ljava/lang/String;->length()I\nmove-result v0\nreturn v0', 1) +
		method('public charAt(I)C', 'iget-object v0, p0, ${sequence}->value:Ljava/lang/String;\ninvoke-virtual {v0, p1}, Ljava/lang/String;->charAt(I)C\nmove-result v0\nreturn v0', 1) +
		method('public subSequence(II)Ljava/lang/CharSequence;', 'iget-object v0, p0, ${sequence}->value:Ljava/lang/String;\ninvoke-virtual {v0, p1, p2}, Ljava/lang/String;->substring(II)Ljava/lang/String;\nmove-result-object v0\nreturn-object v0', 1) +
		method('public toString()Ljava/lang/String;', 'const-string v0, "Wrong toString content"\nreturn-object v0', 1)
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Paint text widths fixture"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\ninvoke-static {}, ${probe}->run()V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2)
}

fn file_hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	started := time.utc().str()
	r := os.exec(args)
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({
		'argv':             json2.Any(args)
		'started_utc':      json2.Any(started)
		'completed_utc':    json2.Any(time.utc().str())
		'exit_code':        json2.Any(r.exit_code)
		'input_sha256':     json2.decode[json2.Any](json2.encode(pins))!
		'generator_sha256': json2.Any(file_hash(os.executable())!)
	},
		prettify: true
	) + '\n')!
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">Paint text widths fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Paint text widths fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/PaintTextWidthsProbe.smali', probe_class())!
	os.write_file(root + '/WidthSequence.smali', sequence_class())!
	tools := os.getenv('PAINT_TEXT_WIDTHS_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' {
		os.abs_path('build/android-native-ws/aapt2')
	} else {
		tools + '/aapt2'
	}
	signer := if tools == '' {
		os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar')
	} else {
		tools + '/apksigner.jar'
	}
	framework := if tools == '' {
		'/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	} else {
		tools + '/framework-res.apk'
	}
	smali := if tools == '' {
		os.abs_path('build/android-framework/tools')
	} else {
		tools + '/smali'
	}
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = file_hash(path)! }
	for name in os.ls(smali)! {
		if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! }
	}
	assert pins.len > 6
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml',
		'-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali',
		'-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname',
		'CN=Vinix Paint text widths fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk',
		out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('PAINT-TEXT-WIDTHS-APK ' + file_hash(out + '/probe.apk')!)
}
