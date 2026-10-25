// SPDX-License-Identifier: GPL-2.0-or-later
// Android/ARM JNI regression: Path Boolean geometry, ownership and contracts.
module main

import crypto.sha256
import json2
import os
import time

const owner = 'Lorg/vinix/bootstrap/PathOpsProbe;'
const path_class = 'Landroid/graphics/Path;'
const canvas_class = 'Landroid/graphics/Canvas;'
const bitmap_class = 'Landroid/graphics/Bitmap;'
const fill_class = 'Landroid/graphics/Path$FillType;'
const op_class = 'Landroid/graphics/Path$Op;'
const fills = ['WINDING', 'EVEN_ODD', 'INVERSE_WINDING', 'INVERSE_EVEN_ODD']
const operations = ['DIFFERENCE', 'INTERSECT', 'UNION', 'XOR', 'REVERSE_DIFFERENCE']

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn scalar(register string, value f32) string {
	return 'const ${register}, 0x' + unsafe { *(&u32(&value)) }.hex() + '\n'
}

// Explicit vertices independently exercise contour orientation and open fills.
fn contour(points [][]f32, closed bool) string {
	mut body := ''
	for i, point in points {
		body += scalar('v0', point[0]) + scalar('v1', point[1])
		body += 'invoke-virtual {v6, v0, v1}, ${path_class}->' +
			if i == 0 { 'moveTo' } else { 'lineTo' } + '(FF)V\n'
	}
	if closed { body += 'invoke-virtual {v6}, ${path_class}->close()V\n' }
	return body
}

fn rectangle(left f32, top f32, right f32, bottom f32, opposite bool) string {
	return contour(if opposite {
		[[left, top], [left, bottom], [right, bottom], [right, top]]
	} else {
		[[left, top], [right, top], [right, bottom], [left, bottom]]
	}, false)
}

fn new_path() string {
	return 'new-instance v6, ${path_class}\ninvoke-direct {v6}, ${path_class}-><init>()V\n'
}

fn set_fill(index int) string {
	return 'sget-object v0, ${fill_class}->${fills[index]}:${fill_class}\n' +
		'invoke-virtual {v6, v0}, ${path_class}->setFillType(${fill_class})V\n'
}

fn shape(kind string, left bool) string {
	if !left {
		return match kind {
			'coincident' { rectangle(2, 2, 10, 10, true) }
			'touching' { rectangle(10, 2, 14, 10, false) }
			'disjoint' { rectangle(11, 11, 14, 14, false) }
			'nested', 'hole' { rectangle(8, 1, 13, 15, false) }
			else { rectangle(6, 6, 14, 14, false) }
		}
	}
	return match kind {
		'empty' { '' }
		'nested', 'hole' {
			rectangle(2, 2, 14, 14, false) + rectangle(5, 5, 11, 11, kind == 'hole')
		}
		'diagonal' { contour([[f32(2), 2], [f32(14.25), 2], [f32(2), 14.25]], false) }
		'curve' {
			contour([[f32(2), 10]], false) + scalar('v0', 8) + scalar('v1', 2) +
				scalar('v2', 14) + scalar('v3', 10) +
				'invoke-virtual {v6, v0, v1, v2, v3}, ${path_class}->quadTo(FFFF)V\n' +
				scalar('v0', 14) + scalar('v1', 14) +
				'invoke-virtual {v6, v0, v1}, ${path_class}->lineTo(FF)V\n' +
				scalar('v0', 2) + scalar('v1', 14) +
				'invoke-virtual {v6, v0, v1}, ${path_class}->lineTo(FF)V\n'
		}
		else { rectangle(2, 2, 10, 10, false) }
	}
}

fn in_rect(x f64, y f64, left f64, top f64, right f64, bottom f64) bool {
	return x >= left && x < right && y >= top && y < bottom
}

// The oracle uses analytic regions and Boolean truth tables, never result paths.
fn inside(kind string, left bool, fill int, x f64, y f64) bool {
	mut result := false
	if !left {
		result = match kind {
			'coincident' { in_rect(x, y, 2, 2, 10, 10) }
			'touching' { in_rect(x, y, 10, 2, 14, 10) }
			'disjoint' { in_rect(x, y, 11, 11, 14, 14) }
			'nested', 'hole' { in_rect(x, y, 8, 1, 13, 15) }
			else { in_rect(x, y, 6, 6, 14, 14) }
		}
	} else {
		result = match kind {
			'empty' { false }
			'nested', 'hole' {
				in_rect(x, y, 2, 2, 14, 14) &&
					(!(kind == 'hole' || fill & 1 == 1) || !in_rect(x, y, 5, 5, 11, 11))
			}
			'diagonal' { x >= 2 && y >= 2 && x + y < 16.25 }
			'curve' {
				t := (x - 2) / 12
				x >= 2 && x < 14 && y >= 10 - 16 * t + 16 * t * t && y < 14
			}
			else { in_rect(x, y, 2, 2, 10, 10) }
		}
	}
	return result != (fill >= 2)
}

fn truth(left bool, right bool, operation int) bool {
	return match operation {
		0 { left && !right }
		1 { left && right }
		2 { left || right }
		3 { left != right }
		4 { right && !left }
		else { panic('invalid operation') }
	}
}

fn mask(kind string, afill int, bfill int, operation int, operand int, same bool) []u32 {
	mut rows := []u32{len: 16}
	for y in 1 .. 15 {
		for x in 1 .. 15 {
			a := inside(kind, true, afill, f64(x) + 0.5, f64(y) + 0.5)
			b := if same { a } else { inside(kind, false, bfill, f64(x) + 0.5, f64(y) + 0.5) }
			covered := match operand {
				1 { a }
				2 { b }
				else { truth(a, b, operation) }
			}
			if covered { rows[y] |= u32(1) << x }
		}
	}
	return rows
}

// These fixtures have no subpixel regions. A constant truth value inside and
// outside all their contours means the operation has no boundary geometry;
// inverse fill can still make such an empty Path cover the whole plane.
fn boundary_empty(kind string, afill int, bfill int, operation int, same bool) bool {
	outside := truth(afill >= 2, if same { afill >= 2 } else { bfill >= 2 }, operation)
	for y in 0 .. 16 {
		for x in 0 .. 16 {
			a := inside(kind, true, afill, f64(x) + 0.5, f64(y) + 0.5)
			b := if same { a } else { inside(kind, false, bfill, f64(x) + 0.5, f64(y) + 0.5) }
			if truth(a, b, operation) != outside { return false }
		}
	}
	return true
}

fn marker(name string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "BOOTSTRAP-PATH-OPS-${name}-PASS"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn target() string {
	return 'const/16 v0, 16\nsget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\n' +
		'invoke-static {v0, v0, v1}, ${bitmap_class}->createBitmap(IILandroid/graphics/Bitmap$Config;)${bitmap_class}\nmove-result-object v8\n' +
		'const/4 v0, 0\ninvoke-virtual {v8, v0}, ${bitmap_class}->eraseColor(I)V\n' +
		'new-instance v7, ${canvas_class}\ninvoke-direct {v7, v8}, ${canvas_class}-><init>(${bitmap_class})V\n' +
		'const/4 v0, 1\nconst/16 v1, 15\ninvoke-virtual {v7, v0, v0, v1, v1}, ${canvas_class}->clipRect(IIII)Z\n' +
		'new-instance v9, Landroid/graphics/Paint;\ninvoke-direct {v9}, Landroid/graphics/Paint;-><init>()V\n' +
		'const v0, 0xff336699\ninvoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColor(I)V\n' +
		'const/4 v0, 0\ninvoke-virtual {v9, v0}, Landroid/graphics/Paint;->setAntiAlias(Z)V\n'
}

fn draw() string {
	return 'invoke-virtual {v7, v6, v9}, ${canvas_class}->drawPath(${path_class}Landroid/graphics/Paint;)V\n'
}

fn verify(rows []u32, label string) string {
	assert rows.len == 16
	mut body := 'const/16 v0, 16\nnew-array v10, v0, [I\n'
	for i, row in rows { body += 'const/16 v0, ${i}\nconst v1, ${row}\naput v1, v10, v0\n' }
	return body + 'const-string v0, "${label}"\n' +
		'invoke-static {v8, v10, v0}, ${owner}->verify(${bitmap_class}[ILjava/lang/String;)V\n' +
		'invoke-virtual {v8}, ${bitmap_class}->recycle()V\n'
}

fn assert_return(expected bool, label string) string {
	return 'move-result v0\nconst/4 v1, ' + if expected { '1' } else { '0' } +
		'\nconst-string v2, "${label}"\n' +
		'invoke-static {v0, v1, v2}, ${owner}->equal(IILjava/lang/String;)V\n'
}

fn assert_fill(fill int, label string) string {
	return 'invoke-virtual {v6}, ${path_class}->getFillType()${fill_class}\nmove-result-object v0\n' +
		'sget-object v1, ${fill_class}->${fills[fill]}:${fill_class}\nconst-string v2, "${label} fill"\n' +
		'invoke-static {v0, v1, v2}, ${owner}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn assert_empty(expected bool, label string) string {
	return 'invoke-virtual {v6}, ${path_class}->isEmpty()Z\n' +
		assert_return(expected, label + ' isEmpty')
}

fn operands(kind string, afill int, bfill int) string {
	return new_path() + shape(kind, true) + set_fill(afill) + 'move-object v12, v6\n' +
		new_path() + shape(kind, false) + set_fill(bfill) + 'move-object v13, v6\n'
}

fn invoke_op(operation int, mode string) string {
	mut body := 'sget-object v14, ${op_class}->${operations[operation]}:${op_class}\n'
	if mode == 'left' {
		body += 'move-object v6, v12\ninvoke-virtual {v6, v13, v14}, ${path_class}->op(${path_class}${op_class})Z\n'
	} else if mode == 'right' {
		body += 'move-object v6, v13\ninvoke-virtual {v6, v12, v13, v14}, ${path_class}->op(${path_class}${path_class}${op_class})Z\n'
	} else if mode == 'both' {
		body += 'move-object v6, v12\ninvoke-virtual {v6, v6, v6, v14}, ${path_class}->op(${path_class}${path_class}${op_class})Z\n'
	} else {
		// A pre-existing destination must be replaced rather than appended to.
		body += new_path() + rectangle(1, 1, 3, 15, false) + set_fill(2) +
			'invoke-virtual {v6, v12, v13, v14}, ${path_class}->op(${path_class}${path_class}${op_class})Z\n'
	}
	return body
}

fn combination(kind string, afill int, bfill int, operation int, mode string, label string) string {
	mut body := operands(kind, afill, bfill)
	// A shared copy must retain its geometry even when an aliased receiver changes.
	body += 'new-instance v11, ${path_class}\ninvoke-direct {v11, v12}, ${path_class}-><init>(${path_class})V\n'
	body += invoke_op(operation, mode) + assert_return(true, label + ' return')
	outside := truth(afill >= 2, if mode == 'both' { afill >= 2 } else { bfill >= 2 }, operation)
	body += assert_fill(if outside { 3 } else { 1 }, label)
	body += assert_empty(boundary_empty(kind, afill, bfill, operation, mode == 'both'), label)
	body += target() + draw() + verify(mask(kind, afill, bfill, operation, 0, mode == 'both'), label)
	// Snapshot source remains readable after the result has been produced.
	body += 'move-object v6, v11\n' + target() + draw() +
		verify(mask(kind, afill, bfill, operation, 1, false), label + ' source copy')
	if mode == 'distinct' || mode == 'left' {
		body += 'move-object v6, v13\n' + target() + draw() +
			verify(mask(kind, afill, bfill, operation, 2, false), label + ' right preserved')
	}
	if mode == 'distinct' || mode == 'right' {
		body += 'move-object v6, v12\n' + target() + draw() +
			verify(mask(kind, afill, bfill, operation, 1, false), label + ' left preserved')
	}
	return method('private static ${label}()V', body + 'return-void', 16)
}

fn helpers() string {
	mut source := method('private static fail(Ljava/lang/String;III)V', r'new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Path op: "
invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " index="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " actual="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " expected="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 2)
	source += method('private static equal(IILjava/lang/String;)V', 'if-eq p0, p1, :ok\nconst/4 v0, -1\ninvoke-static {p2, v0, p0, p1}, ${owner}->fail(Ljava/lang/String;III)V\n:ok\nreturn-void', 1)
	source += method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 'if-eq p0, p1, :ok\nconst/4 v0, -1\nconst/4 v1, 0\nconst/4 v2, 1\ninvoke-static {p2, v0, v1, v2}, ${owner}->fail(Ljava/lang/String;III)V\n:ok\nreturn-void', 3)
	source += method('private static verify(${bitmap_class}[ILjava/lang/String;)V', r'const/16 v0, 256
new-array v8, v0, [I
move-object v0, p0
move-object v1, v8
const/4 v2, 0
const/16 v3, 16
const/4 v4, 0
const/4 v5, 0
const/16 v6, 16
const/16 v7, 16
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v9, 0
:loop
shr-int/lit8 v0, v9, 4
aget v1, p1, v0
and-int/lit8 v2, v9, 15
ushr-int/2addr v1, v2
and-int/lit8 v1, v1, 1
const/4 v4, 0
if-eqz v1, :expected
const v4, 0xff336699
:expected
aget v3, v8, v9
if-eq v3, v4, :next
invoke-static {p2, v9, v3, v4}, Lorg/vinix/bootstrap/PathOpsProbe;->fail(Ljava/lang/String;III)V
:next
add-int/lit8 v9, v9, 1
const/16 v0, 256
if-lt v9, v0, :loop
return-void', 10)
	source += method('private static traceAbsent()V', '
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
const/4 v1, -1
const/4 v3, 0
const/4 v4, 1
invoke-static {v0, v1, v3, v4}, ${owner}->fail(Ljava/lang/String;III)V
:good
' + marker('TRACE-ENV-ABSENT') + 'return-void', 5)
	return source
}

fn contracts() string {
	mut source := ''
	for kind in ['left', 'right', 'operation', 'twoOperand', 'twoOperation'] {
		mut body := operands('overlap', 2, 0) + 'move-object v6, v12\n' +
			'sget-object v14, ${op_class}->UNION:${op_class}\nconst/4 v0, 0\n:try_start\n'
		body += match kind {
			'left' { 'invoke-virtual {v6, v0, v13, v14}, ${path_class}->op(${path_class}${path_class}${op_class})Z\n' }
			'right' { 'invoke-virtual {v6, v12, v0, v14}, ${path_class}->op(${path_class}${path_class}${op_class})Z\n' }
			'operation' { 'invoke-virtual {v6, v12, v13, v0}, ${path_class}->op(${path_class}${path_class}${op_class})Z\n' }
			'twoOperand' { 'invoke-virtual {v6, v0, v14}, ${path_class}->op(${path_class}${op_class})Z\n' }
			else { 'invoke-virtual {v6, v13, v0}, ${path_class}->op(${path_class}${op_class})Z\n' }
		}
		body += ':try_end\nconst-string v0, "null ${kind} must throw"\nconst/4 v1, -1\nconst/4 v2, 0\nconst/4 v3, 1\ninvoke-static {v0, v1, v2, v3}, ${owner}->fail(Ljava/lang/String;III)V\nreturn-void\n:catch\nmove-exception v0\n'
		body += assert_fill(2, 'null' + kind) + target() + draw() +
			verify(mask('overlap', 2, 0, 0, 1, false), 'null' + kind + ' unchanged') +
			'return-void\n.catch Ljava/lang/NullPointerException; {:try_start .. :try_end} :catch'
		source += method('private static null${kind}()V', body, 16)
	}
	mut body := operands('overlap', 2, 0)
	body += 'move-object v6, v13\ninvoke-virtual {v6}, ${path_class}->reset()V\n'
	body += contour([[f32(2), 2]], false) + 'const v0, 0x7fc00000\n' + scalar('v1', 4) +
		'invoke-virtual {v6, v0, v1}, ${path_class}->lineTo(FF)V\n' + scalar('v0', 10) + scalar('v1', 10) +
		'invoke-virtual {v6, v0, v1}, ${path_class}->lineTo(FF)V\nmove-object v6, v12\n' +
		'sget-object v14, ${op_class}->UNION:${op_class}\n' +
		'invoke-virtual {v6, v13, v14}, ${path_class}->op(${path_class}${op_class})Z\n' +
		assert_return(false, 'NaN returns false') + assert_fill(2, 'NaN') + target() + draw() +
		verify(mask('overlap', 2, 0, 0, 1, false), 'NaN receiver unchanged') + 'return-void'
	source += method('private static invalid()V', body, 16)
	return source
}

fn bounds_and_stroke() string {
	mut body := operands('overlap', 0, 0) + invoke_op(1, 'distinct') + assert_return(true, 'bounds intersection')
	body += 'new-instance v4, Landroid/graphics/RectF;\ninvoke-direct {v4}, Landroid/graphics/RectF;-><init>()V\nconst/4 v0, 0\ninvoke-virtual {v6, v4, v0}, ${path_class}->computeBounds(Landroid/graphics/RectF;Z)V\n'
	for i, field in ['left', 'top', 'right', 'bottom'] {
		body += 'iget v0, v4, Landroid/graphics/RectF;->${field}:F\n' +
			'invoke-static {v0}, Ljava/lang/Float;->floatToIntBits(F)I\nmove-result v0\n' +
			scalar('v1', if i < 2 { f32(6) } else { f32(10) }) +
			'const-string v2, "intersection bounds ${field}"\ninvoke-static {v0, v1, v2}, ${owner}->equal(IILjava/lang/String;)V\n'
	}
	body += 'return-void'
	mut source := method('private static bounds()V', body, 16)
	body = operands('overlap', 0, 0) + invoke_op(2, 'distinct') + assert_return(true, 'stroke union') + target()
	body += 'sget-object v0, Landroid/graphics/Paint$Style;->STROKE:Landroid/graphics/Paint$Style;\ninvoke-virtual {v9, v0}, Landroid/graphics/Paint;->setStyle(Landroid/graphics/Paint$Style;)V\n' +
		scalar('v0', 1) + 'invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setStrokeWidth(F)V\n' + draw()
	for point in [[5, 2, 1], [7, 6, 0], [10, 7, 0], [7, 10, 0], [12, 14, 1]] {
		body += 'const/16 v0, ${point[0]}\nconst/16 v1, ${point[1]}\nconst v2, ' +
			if point[2] == 1 { '0xff336699' } else { '0' } +
			'\ninvoke-static {v8, v0, v1, v2}, ${owner}->pixel(${bitmap_class}III)V\n'
	}
	body += 'invoke-virtual {v8}, ${bitmap_class}->recycle()V\nreturn-void'
	source += method('private static stroke()V', body, 16)
	source += method('private static pixel(${bitmap_class}III)V', 'move-object v0, p0\nconst/4 v2, 1\nnew-array v1, v2, [I\nconst/4 v2, 0\nconst/4 v3, 1\nmove v4, p1\nmove v5, p2\nconst/4 v6, 1\nconst/4 v7, 1\ninvoke-virtual/range {v0 .. v7}, ${bitmap_class}->getPixels([IIIIIII)V\nconst/4 v0, 0\naget v1, v1, v0\nif-eq v1, p3, :ok\nconst-string v0, "union stroke boundary"\ninvoke-static {v0, p1, v1, p3}, ${owner}->fail(Ljava/lang/String;III)V\n:ok\nreturn-void', 8)
	return source
}

fn copy_result() string {
	mut body := operands('overlap', 0, 0) + invoke_op(2, 'distinct') + assert_return(true, 'copy union')
	body += 'new-instance v11, ${path_class}\ninvoke-direct {v11, v6}, ${path_class}-><init>(${path_class})V\ninvoke-virtual {v6}, ${path_class}->reset()V\nmove-object v6, v11\n'
	body += target() + draw() + verify(mask('overlap', 0, 0, 2, 0, false), 'copy result after reset')
	body += 'move-object v12, v6\n' + new_path() +
		'invoke-virtual {v6, v12}, ${path_class}->addPath(${path_class})V\n' + set_fill(1)
	body += target() + draw() + verify(mask('overlap', 0, 0, 2, 0, false), 'add result')
	body += 'new-instance v4, Landroid/graphics/Matrix;\ninvoke-direct {v4}, Landroid/graphics/Matrix;-><init>()V\n' +
		scalar('v0', 1) + scalar('v1', 0) +
		'invoke-virtual {v4, v0, v1}, Landroid/graphics/Matrix;->setTranslate(FF)V\n' +
		'invoke-virtual {v6, v4}, ${path_class}->transform(Landroid/graphics/Matrix;)V\n'
	mut shifted := []u32{len: 16}
	for y, row in mask('overlap', 0, 0, 2, 0, false) { shifted[y] = (row << 1) & 0x7ffe }
	body += target() + draw() + verify(shifted, 'transform result') + 'return-void'
	return method('private static copyResult()V', body, 16)
}

fn empty_state() string {
	// Android Path.isEmpty counts verbs, including a lone moveTo, independently
	// of fill coverage. Copies publish native geometry without drawing it.
	mut body := new_path() + assert_empty(true, 'fresh') + set_fill(3) +
		assert_empty(true, 'inverse fresh') +
		'new-instance v11, ${path_class}\ninvoke-direct {v11, v6}, ${path_class}-><init>(${path_class})V\n' +
		assert_empty(true, 'published empty') +
		'move-object v6, v11\n' + assert_empty(true, 'copied inverse empty') +
		contour([[f32(2), 2]], false) + assert_empty(false, 'builder move only') +
		'new-instance v11, ${path_class}\ninvoke-direct {v11, v6}, ${path_class}-><init>(${path_class})V\n' +
		assert_empty(false, 'published move only') +
		'move-object v6, v11\n' + assert_empty(false, 'copied move only') +
		scalar('v0', 8) + scalar('v1', 8) +
		'invoke-virtual {v6, v0, v1}, ${path_class}->lineTo(FF)V\n' +
		assert_empty(false, 'builder after published move') +
		'invoke-virtual {v6}, ${path_class}->reset()V\n' + assert_empty(true, 'reset') +
		set_fill(2) + assert_empty(true, 'inverse reset') +
		rectangle(2, 2, 10, 10, false) + assert_empty(false, 'builder rectangle') +
		'new-instance v11, ${path_class}\ninvoke-direct {v11, v6}, ${path_class}-><init>(${path_class})V\n' +
		assert_empty(false, 'published rectangle') +
		'invoke-virtual {v6}, ${path_class}->reset()V\n' + assert_empty(true, 'published reset') +
		'move-object v6, v11\n' + assert_empty(false, 'copy survives source reset') + 'return-void'
	return method('private static emptyState()V', body, 16)
}

fn probe() string {
	mut source := '.class public ${owner}\n.super Ljava/lang/Object;\n' + helpers() + contracts() + bounds_and_stroke() + copy_result() + empty_state()
	mut run := 'invoke-static {}, ${owner}->traceAbsent()V\n' + operands('overlap', 0, 0) +
		invoke_op(2, 'left') + 'move-result v0\nif-nez v0, :supported\n' +
		assert_fill(0, 'baseline receiver') + target() + draw() +
		verify(mask('overlap', 0, 0, 2, 1, false), 'baseline false receiver unchanged') +
		'move-object v6, v13\n' + target() + draw() +
		verify(mask('overlap', 0, 0, 2, 2, false), 'baseline right unchanged') + marker('EXPECTED-STUB') +
		'const/4 v0, 0\nreturn v0\n:supported\n'
	for afill in 0 .. 4 {
		for bfill in 0 .. 4 {
			for operation in 0 .. 5 {
				name := 'matrix${afill}${bfill}${operation}'
				source += combination('overlap', afill, bfill, operation, 'distinct', name)
				run += 'invoke-static {}, ${owner}->${name}()V\n'
			}
		}
	}
	run += marker('MATRIX')
	for kind in ['nested', 'hole', 'diagonal', 'curve', 'empty', 'coincident', 'touching', 'disjoint'] {
		for pair in [[0, 0], [1, 0], [2, 3], [3, 2]] {
			for operation in 0 .. 5 {
				name := '${kind}${pair[0]}${pair[1]}${operation}'
				source += combination(kind, pair[0], pair[1], operation, 'distinct', name)
				run += 'invoke-static {}, ${owner}->${name}()V\n'
			}
		}
	}
	run += marker('SHAPES')
	for mode in ['left', 'right', 'both'] {
		for operation in 0 .. 5 {
			name := '${mode}${operation}'
			source += combination('overlap', 0, 0, operation, mode, name)
			run += 'invoke-static {}, ${owner}->${name}()V\n'
		}
	}
	run += 'invoke-static {}, ${owner}->copyResult()V\n' + marker('ALIASES')
	for kind in ['left', 'right', 'operation', 'twoOperand', 'twoOperation'] {
		run += 'invoke-static {}, ${owner}->null${kind}()V\n'
	}
	run += 'invoke-static {}, ${owner}->invalid()V\ninvoke-static {}, ${owner}->bounds()V\ninvoke-static {}, ${owner}->stroke()V\ninvoke-static {}, ${owner}->emptyState()V\n' +
		marker('CONTRACTS') + 'const/4 v0, 1\nreturn v0'
	source += method('public static run()Z', run, 16)
	return source
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\n' +
			'new-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\n' +
			'const-string v1, "Path operations JNI fixture"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\n' +
			'invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\n' +
			'invoke-static {}, ${owner}->run()Z\nmove-result v0\nif-eqz v0, :ready\n' +
			'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-PATH-OPS-PASS"\n' +
			'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n:ready\n' +
			'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\n' +
			'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2)
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
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Path operations fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/PathOpsProbe.smali', probe())!
	tools := os.getenv('PATH_OPS_FIXTURE_TOOLS_ROOT')
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
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Path operations fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('PATH-OPS-APK ' + file_hash(out + '/probe.apk')!)
}
