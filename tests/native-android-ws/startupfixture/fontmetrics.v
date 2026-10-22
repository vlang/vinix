// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os
import math

fn metric_u16(data []u8, at int) int { return int(u16(data[at]) << 8 | u16(data[at + 1])) }
fn metric_table(data []u8, name string) !int {
	for i in 0 .. metric_u16(data, 4) {
		at := 12 + i * 16
		if data[at..at + 4].bytestr() == name {
			return int(u32(data[at + 8]) << 24 | u32(data[at + 9]) << 16 | u32(data[at + 10]) << 8 | u32(data[at + 11]))
		}
	}
	return error('missing TrueType table ' + name)
}

// Independent expectations read the font's head/hhea tables, without stb.
fn metric_expected(path string, size f32) ![]f32 {
	data := os.read_bytes(path)!
	h, v := metric_table(data, 'head')!, metric_table(data, 'hhea')!
	a, d := int(i16(metric_u16(data, v + 4))), int(i16(metric_u16(data, v + 6)))
	scale := size / f32(a - d)
	return [-f32(i16(metric_u16(data, h + 42))) * scale, -f32(a) * scale,
		-f32(d) * scale, -f32(i16(metric_u16(data, h + 38))) * scale,
		f32(i16(metric_u16(data, v + 8))) * scale]
}

fn metric_float_check(expected f32) string {
	return 'const v4, 0x${math.f32_bits(expected).hex()}\nsub-float/2addr v3, v4\ninvoke-static {v3}, Ljava/lang/Math;->abs(F)F\nmove-result v3\nconst v4, 0x3a83126f\ncmpg-float v3, v3, v4\nif-gtz v3, :bad\n'
}

fn metric_check_method(name string, expected []f32) string {
	mut body := '
new-instance v1, Landroid/graphics/Paint$FontMetrics;
invoke-direct {v1}, Landroid/graphics/Paint$FontMetrics;-><init>()V
new-instance v2, Landroid/graphics/Paint$FontMetricsInt;
invoke-direct {v2}, Landroid/graphics/Paint$FontMetricsInt;-><init>()V
const/high16 v3, 0x42c60000
const/16 v4, 99
'
	fields := ['top', 'ascent', 'descent', 'bottom', 'leading']
	for field in fields {
		body += 'iput v3, v1, Landroid/graphics/Paint$FontMetrics;->${field}:F\niput v4, v2, Landroid/graphics/Paint$FontMetricsInt;->${field}:I\n'
	}
	spacing := expected[2] - expected[1] + expected[4]
	mut ints := []int{}
	for i, value in expected { ints << int(if i == 0 { math.floor(value) } else if i == 3 { math.ceil(value) } else { math.floor(value + f32(0.5)) }) }
	line := ints[2] - ints[1] + ints[4]
	for target in ['v1', 'v5'] {
		if target == 'v5' { body += 'invoke-virtual {p0}, Landroid/graphics/Paint;->getFontMetrics()Landroid/graphics/Paint$FontMetrics;\nmove-result-object v5\nif-eq v1, v5, :bad\n' }
		else { body += 'invoke-virtual {p0, v1}, Landroid/graphics/Paint;->getFontMetrics(Landroid/graphics/Paint$FontMetrics;)F\nmove-result v3\n' + metric_float_check(spacing) }
		for i, field in fields { body += 'iget v3, ${target}, Landroid/graphics/Paint$FontMetrics;->${field}:F\n' + metric_float_check(expected[i]) }
	}
	for target in ['v2', 'v5'] {
		if target == 'v5' { body += 'invoke-virtual {p0}, Landroid/graphics/Paint;->getFontMetricsInt()Landroid/graphics/Paint$FontMetricsInt;\nmove-result-object v5\nif-eq v2, v5, :bad\n' }
		else { body += 'invoke-virtual {p0, v2}, Landroid/graphics/Paint;->getFontMetricsInt(Landroid/graphics/Paint$FontMetricsInt;)I\nmove-result v3\nconst v4, ${line}\nif-ne v3, v4, :bad\n' }
		for i, field in fields { body += 'iget v3, ${target}, Landroid/graphics/Paint$FontMetricsInt;->${field}:I\nconst v4, ${ints[i]}\nif-ne v3, v4, :bad\n' }
	}
	body += 'const/4 v1, 0\ninvoke-virtual {p0, v1}, Landroid/graphics/Paint;->getFontMetrics(Landroid/graphics/Paint$FontMetrics;)F\nmove-result v3\n' + metric_float_check(spacing)
	body += 'invoke-virtual {p0, v1}, Landroid/graphics/Paint;->getFontMetricsInt(Landroid/graphics/Paint$FontMetricsInt;)I\nmove-result v3\nconst v4, ${line}\nif-ne v3, v4, :bad\n'
	for signature, value in {'ascent': expected[1], 'descent': expected[2], 'getFontSpacing': spacing} {
		body += 'invoke-virtual {p0}, Landroid/graphics/Paint;->${signature}()F\nmove-result v3\n' + metric_float_check(value)
	}
	body += 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Paint font metrics ${name}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	return method('private static ${name}(Landroid/graphics/Paint;)V', body)
}

fn install_font_metrics_probe(dir string, runtime string) ! {
	fonts := runtime + '/usr/share/fonts/dejavu/'
	mut text := '.class public Lorg/vinix/bootstrap/FontMetricsProbe;\n.super Ljava/lang/Object;\n'
	for row in [['sans', 'DejaVuSans', '24'], ['large', 'DejaVuSans', '1192'], ['serif', 'DejaVuSerif-Bold', '24'], ['resource', 'DejaVuSansMono', '24'], ['zero', 'DejaVuSans', '0'], ['reset', 'DejaVuSans', '16']] {
		text += metric_check_method(row[0], metric_expected(fonts + row[1] + '.ttf', row[2].f32())!)
	}
	text += method('public static check(Landroid/content/Context;)V', '
new-instance v0, Landroid/graphics/Paint;
invoke-direct {v0}, Landroid/graphics/Paint;-><init>()V
const/high16 v1, 0x41c00000
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V
invoke-static {v0}, Lorg/vinix/bootstrap/FontMetricsProbe;->sans(Landroid/graphics/Paint;)V
# Exact negative half-unit ascent exercises Java rounding toward +infinity.
const v1, 0x44950000
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V
invoke-static {v0}, Lorg/vinix/bootstrap/FontMetricsProbe;->large(Landroid/graphics/Paint;)V
const/high16 v1, 0x41c00000
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V
const-string v1, "serif"
const/4 v2, 1
invoke-static {v1, v2}, Landroid/graphics/Typeface;->create(Ljava/lang/String;I)Landroid/graphics/Typeface;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;
invoke-static {v0}, Lorg/vinix/bootstrap/FontMetricsProbe;->serif(Landroid/graphics/Paint;)V
new-instance v3, Landroid/graphics/Paint;
invoke-direct {v3, v0}, Landroid/graphics/Paint;-><init>(Landroid/graphics/Paint;)V
invoke-virtual {v0}, Landroid/graphics/Paint;->reset()V
invoke-static {v0}, Lorg/vinix/bootstrap/FontMetricsProbe;->reset(Landroid/graphics/Paint;)V
invoke-static {v3}, Lorg/vinix/bootstrap/FontMetricsProbe;->serif(Landroid/graphics/Paint;)V
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v1
const-string v2, "fixture_font"
const-string v4, "font"
const-string v5, "org.vinix.bootstrap"
invoke-virtual {v1, v2, v4, v5}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v2
invoke-virtual {v1, v2}, Landroid/content/res/Resources;->getFont(I)Landroid/graphics/Typeface;
move-result-object v1
invoke-virtual {v3, v1}, Landroid/graphics/Paint;->setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;
invoke-static {v3}, Lorg/vinix/bootstrap/FontMetricsProbe;->resource(Landroid/graphics/Paint;)V
const/4 v1, 0
invoke-virtual {v3, v1}, Landroid/graphics/Paint;->setTextSize(F)V
invoke-static {v3}, Lorg/vinix/bootstrap/FontMetricsProbe;->zero(Landroid/graphics/Paint;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-FONT-METRICS-PASS font-tables floats integers bounds rounding negative-half null reuse scale typeface resource copy reset zero"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void')
	os.write_file(dir + '/FontMetricsProbe.smali', text)!
}
