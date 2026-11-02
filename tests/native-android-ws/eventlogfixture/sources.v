// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const poison_type = 'Lorg/vinix/bootstrap/Poison;'
const event_type = 'Landroid/util/EventLog;'
const pass_marker = 'EVENT-LOG-PASS five-overloads public-static varargs null-types prefix-255 encoding-boundaries error-order unchanged-arrays unavailable-backend'
const fail_marker = 'EVENT-LOG-FAIL'
const fixture_scope = 'Standalone API-28 EventLog write overload linkage, public/static primitive-int and varargs metadata, accepted scalar/null/boxed payloads, exact invalid-item exceptions, first-255-item selection, target ART UTF byte-budget boundaries, encoding-error precedence and unchanged caller arrays. Accepted payloads return -ENODEV because the binary event backend is unavailable; earlier encoding failures retain -EIO. No event storage, positive delivery, payload readback, readEvents API, logcat/stdout substitution, Google task completion, cross-process, account or authentication success is supplied.'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn helpers_source() string {
	return method('private static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static copy([Ljava/lang/Object;)[Ljava/lang/Object;', 4, '
if-nez p0, :nonnull
const/4 v0, 0
return-object v0
:nonnull
array-length v0, p0
new-array v1, v0, [Ljava/lang/Object;
const/4 v2, 0
:next
if-ge v2, v0, :done
aget-object v3, p0, v2
aput-object v3, v1, v2
add-int/lit8 v2, v2, 1
goto :next
:done
return-object v1') + method('private static unchanged([Ljava/lang/Object;[Ljava/lang/Object;)V', 6, '
const-string v5, "EventLog must preserve every caller array reference"
if-nez p0, :nonnull
invoke-static {p0, p1, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void
:nonnull
array-length v0, p0
array-length v1, p1
invoke-static {v0, v1, v5}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v2, 0
:next
if-ge v2, v0, :done
aget-object v3, p0, v2
aget-object v4, p1, v2
invoke-static {v3, v4, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
add-int/lit8 v2, v2, 1
goto :next
:done
return-void') + method('private static status([Ljava/lang/Object;I)V', 4, '
invoke-static {p0}, ${main_type}->copy([Ljava/lang/Object;)[Ljava/lang/Object;
move-result-object v0
const v1, 0x31ce5
invoke-static {v1, p0}, ${event_type}->writeEvent(I[Ljava/lang/Object;)I
move-result v1
const-string v2, "EventLog must preserve the preparation result before the unavailable backend"
invoke-static {v1, p1, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {p0, v0}, ${main_type}->unchanged([Ljava/lang/Object;[Ljava/lang/Object;)V
return-void') + method('private static reject([Ljava/lang/Object;)V', 5, '
invoke-static {p0}, ${main_type}->copy([Ljava/lang/Object;)[Ljava/lang/Object;
move-result-object v0
const v1, 0x31ce5
:attempt_start
invoke-static {v1, p0}, ${event_type}->writeEvent(I[Ljava/lang/Object;)I
:attempt_end
new-instance v1, Ljava/lang/AssertionError;
const-string v2, "processed unsupported payload must throw before backend status"
invoke-direct {v1, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:denied
move-exception v1
invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v2
const-class v3, Ljava/lang/IllegalArgumentException;
const-string v4, "unsupported payload must throw exactly IllegalArgumentException"
invoke-static {v2, v3, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v1
const-string v2, "Invalid payload item type"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
const/4 v2, 1
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {p0, v0}, ${main_type}->unchanged([Ljava/lang/Object;[Ljava/lang/Object;)V
return-void
.catch Ljava/lang/IllegalArgumentException; {:attempt_start .. :attempt_end} :denied')
}

fn shape_source() string {
	mut body := method('private static shape(Ljava/lang/Class;Z)V', 5, '
const/4 v0, 2
new-array v0, v0, [Ljava/lang/Class;
sget-object v1, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
const/4 v2, 0
aput-object v1, v0, v2
const/4 v2, 1
aput-object p0, v0, v2
const-class v1, ${event_type}
const-string v2, "writeEvent"
invoke-virtual {v1, v2, v0}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;
move-result-object v2
const-string v4, "all five overloads must be declared by EventLog"
invoke-static {v2, v1, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
sget-object v2, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
const-string v4, "writeEvent must return primitive int"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v1
and-int/lit8 v1, v1, 9
const/16 v2, 9
const-string v4, "writeEvent overloads must be public static"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->isVarArgs()Z
move-result v1
const-string v4, "only the Object-array overload must have varargs metadata"
invoke-static {v1, p1, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
	body += method('private static shapes()V', 2, '
const/4 v1, 0
sget-object v0, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
invoke-static {v0, v1}, ${main_type}->shape(Ljava/lang/Class;Z)V
sget-object v0, Ljava/lang/Long;->TYPE:Ljava/lang/Class;
invoke-static {v0, v1}, ${main_type}->shape(Ljava/lang/Class;Z)V
sget-object v0, Ljava/lang/Float;->TYPE:Ljava/lang/Class;
invoke-static {v0, v1}, ${main_type}->shape(Ljava/lang/Class;Z)V
const-class v0, Ljava/lang/String;
invoke-static {v0, v1}, ${main_type}->shape(Ljava/lang/Class;Z)V
const-class v0, [Ljava/lang/Object;
const/4 v1, 1
invoke-static {v0, v1}, ${main_type}->shape(Ljava/lang/Class;Z)V
return-void')
	return body
}

fn chars_source() string {
	return method('private static chars(II)Ljava/lang/String;', 4, '
new-array v0, p0, [C
const/4 v1, 0
:next
if-ge v1, p0, :text
aput-char p1, v0, v1
add-int/lit8 v1, v1, 1
goto :next
:text
new-instance v2, Ljava/lang/String;
invoke-direct {v2, v0}, Ljava/lang/String;-><init>([C)V
return-object v2') + method('private static pair()Ljava/lang/String;', 4, '
const/4 v0, 2
new-array v0, v0, [C
const v1, 0xd83d
const/4 v2, 0
aput-char v1, v0, v2
const v1, 0xde00
const/4 v2, 1
aput-char v1, v0, v2
new-instance v3, Ljava/lang/String;
invoke-direct {v3, v0}, Ljava/lang/String;-><init>([C)V
return-object v3') + method('private static filled(ILjava/lang/Object;)[Ljava/lang/Object;', 2, '
new-array v0, p0, [Ljava/lang/Object;
const/4 v1, 0
:next
if-ge v1, p0, :done
aput-object p1, v0, v1
add-int/lit8 v1, v1, 1
goto :next
:done
return-object v0')
}

fn scalar_check(descriptor string, registers string) string {
	return 'invoke-static {${registers}}, ${event_type}->writeEvent(${descriptor})I\nmove-result v4\n' +
		'const/16 v5, -19\nconst-string v6, "valid scalar payload must report unavailable binary event backend"\n' +
		'invoke-static {v4, v5, v6}, ${main_type}->equal(IILjava/lang/String;)V\n'
}

fn scalars_source() string {
	mut body := ''
	for tag in ['0', '-1', '0x7fffffff', '0x31ce5'] {
		body += 'const v0, ${tag}\nconst v1, 0x12345\n' + scalar_check('II', 'v0, v1')
		body += 'const-wide v1, 0x100000001L\n' + scalar_check('IJ', 'v0, v1, v2')
		body += 'const v1, 0x3fc00000\n' + scalar_check('IF', 'v0, v1')
		body += 'const-string v1, "event-fixture"\n' + scalar_check('ILjava/lang/String;', 'v0, v1')
	}
	body += 'const v0, 0x31ce5\n'
	for value in ['0', '-1', '0x80000000', '0x7fffffff'] {
		body += 'const v1, ${value}\n' + scalar_check('II', 'v0, v1')
	}
	for value in ['0x0L', '-0x1L', '-0x8000000000000000L', '0x7fffffffffffffffL'] {
		body += 'const-wide v1, ${value}\n' + scalar_check('IJ', 'v0, v1, v2')
	}
	for bits in ['0x0', '0x80000000', '0x7fc00000', '0x7f800000', '0xff800000'] {
		body += 'const v1, ${bits}\n' + scalar_check('IF', 'v0, v1')
	}
	body += 'const/4 v1, 0\n' + scalar_check('ILjava/lang/String;', 'v0, v1')
	for value in ['""', '"NULL"', '"[NULL]"', '"vinix-使用-Δ"'] {
		body += 'const-string v1, ${value}\n' + scalar_check('ILjava/lang/String;', 'v0, v1')
	}
	body += 'const/16 v1, 6000\nconst/16 v2, 0x61\ninvoke-static {v1, v2}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v1\n' +
		scalar_check('ILjava/lang/String;', 'v0, v1')
	body += 'return-void'
	return method('private static scalars()V', 7, body)
}

// Loads real Java payload values. Scratch registers follow the result register.
fn value_source(kind string, target int) string {
	tmp := target + 1
	return match kind {
		'integer' { 'const v${tmp}, 0x12345\ninvoke-static {v${tmp}}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;\nmove-result-object v${target}\n' }
		'long' { 'const-wide v${tmp}, 0x100000001L\ninvoke-static {v${tmp}, v${tmp + 1}}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;\nmove-result-object v${target}\n' }
		'float' { 'const v${tmp}, 0x7fc00000\ninvoke-static {v${tmp}}, Ljava/lang/Float;->valueOf(F)Ljava/lang/Float;\nmove-result-object v${target}\n' }
		'string' { 'const-string v${target}, "payload"\n' }
		'null' { 'const/4 v${target}, 0\n' }
		'boolean' { 'sget-object v${target}, Ljava/lang/Boolean;->TRUE:Ljava/lang/Boolean;\n' }
		'double' { 'const-wide v${tmp}, 0x3ff0000000000000L\ninvoke-static {v${tmp}, v${tmp + 1}}, Ljava/lang/Double;->valueOf(D)Ljava/lang/Double;\nmove-result-object v${target}\n' }
		'byte' { 'const/4 v${tmp}, 1\ninvoke-static {v${tmp}}, Ljava/lang/Byte;->valueOf(B)Ljava/lang/Byte;\nmove-result-object v${target}\n' }
		'short' { 'const/4 v${tmp}, 1\ninvoke-static {v${tmp}}, Ljava/lang/Short;->valueOf(S)Ljava/lang/Short;\nmove-result-object v${target}\n' }
		'character' { 'const/16 v${tmp}, 0x61\ninvoke-static {v${tmp}}, Ljava/lang/Character;->valueOf(C)Ljava/lang/Character;\nmove-result-object v${target}\n' }
		'int-array' { 'const/4 v${tmp}, 0\nnew-array v${target}, v${tmp}, [I\n' }
		'object-array' { 'const/4 v${tmp}, 0\nnew-array v${target}, v${tmp}, [Ljava/lang/Object;\n' }
		'poison' { 'move-object v${target}, p0\n' }
		else { panic('unknown fixture value: ' + kind) }
	}
}

fn lists_source() string {
	mut body := '
const/4 v0, 0
const/16 v1, -19
invoke-static {v0, v1}, ${main_type}->status([Ljava/lang/Object;I)V
const/4 v0, 0
new-array v0, v0, [Ljava/lang/Object;
invoke-static {v0, v1}, ${main_type}->status([Ljava/lang/Object;I)V
'
	for kind in ['integer', 'long', 'float', 'string', 'null', 'boolean', 'double', 'byte',
		'short', 'character', 'int-array', 'object-array', 'poison'] {
		body += value_source(kind, 0) + 'const/4 v1, 1\ninvoke-static {v1, v0}, ${main_type}->filled(ILjava/lang/Object;)[Ljava/lang/Object;\nmove-result-object v0\n'
		body += if kind in ['integer', 'long', 'float', 'string', 'null'] {
			'const/16 v1, -19\ninvoke-static {v0, v1}, ${main_type}->status([Ljava/lang/Object;I)V\n'
		} else {
			'invoke-static {v0}, ${main_type}->reject([Ljava/lang/Object;)V\n'
		}
	}
	body += '
const/4 v0, 5
new-array v0, v0, [Ljava/lang/Object;
'
	for index, kind in ['integer', 'long', 'float', 'string', 'null'] {
		body += value_source(kind, 1) + 'const/4 v4, ${index}\naput-object v1, v0, v4\n'
	}
	body += '
const/16 v1, -19
invoke-static {v0, v1}, ${main_type}->status([Ljava/lang/Object;I)V
invoke-static {v0, v1}, ${main_type}->status([Ljava/lang/Object;I)V
return-void'
	return method('private static lists(${poison_type})V', 6, body)
}

fn prefix_source() string {
	return method('private static prefix(${poison_type})V', 5, '
const/4 v0, 7
invoke-static {v0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v0
const/16 v1, 256
invoke-static {v1, v0}, ${main_type}->filled(ILjava/lang/Object;)[Ljava/lang/Object;
move-result-object v1
const/16 v2, 255
aput-object p0, v1, v2
const/16 v3, -19
invoke-static {v1, v3}, ${main_type}->status([Ljava/lang/Object;I)V
const/16 v2, 254
aput-object p0, v1, v2
invoke-static {v1}, ${main_type}->reject([Ljava/lang/Object;)V
aput-object v0, v1, v2
invoke-static {v1, v3}, ${main_type}->status([Ljava/lang/Object;I)V
const/16 v2, 255
aput-object v0, v1, v2
invoke-static {v1, v3}, ${main_type}->status([Ljava/lang/Object;I)V
return-void')
}

// A later invalid item makes successful/failed preparation observably distinct.
// This does not reproduce the platform encoder or claim any stored bytes.
fn boundary_source() string {
	return method('private static boundary(Ljava/lang/String;${poison_type}Z)V', 5, '
const/4 v0, 3
new-array v0, v0, [Ljava/lang/Object;
const/4 v1, 0
aput-object p0, v0, v1
const/4 v1, 0
invoke-static {v1}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v1
const/4 v2, 1
aput-object v1, v0, v2
const/4 v1, 2
aput-object p1, v0, v1
if-eqz p2, :invalid_reached
const/4 v1, -5
invoke-static {v0, v1}, ${main_type}->status([Ljava/lang/Object;I)V
return-void
:invalid_reached
invoke-static {v0}, ${main_type}->reject([Ljava/lang/Object;)V
return-void')
}

fn size_source() string {
	mut body := ''
	for length in [4057, 4058, 6000] {
		body += 'const/16 v0, ${length}\nconst/16 v1, 0x61\ninvoke-static {v0, v1}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v0\n' +
			'const/4 v1, 1\ninvoke-static {v1, v0}, ${main_type}->filled(ILjava/lang/Object;)[Ljava/lang/Object;\nmove-result-object v1\nconst/16 v2, -19\ninvoke-static {v1, v2}, ${main_type}->status([Ljava/lang/Object;I)V\n' +
			'const/4 v1, 2\nnew-array v1, v1, [Ljava/lang/Object;\nconst/4 v2, 0\naput-object v0, v1, v2\nconst/4 v2, 1\naput-object p0, v1, v2\ninvoke-static {v1}, ${main_type}->reject([Ljava/lang/Object;)V\n' +
			'const/4 v1, 1\ninvoke-static {v0, p0, v1}, ${main_type}->boundary(Ljava/lang/String;${poison_type}Z)V\n'
	}
	for length in [4052, 4053] {
		body += 'const/16 v0, ${length}\nconst/16 v1, 0x61\ninvoke-static {v0, v1}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v0\nconst/4 v1, ${if length == 4052 { 0 } else { 1 }}\ninvoke-static {v0, p0, v1}, ${main_type}->boundary(Ljava/lang/String;${poison_type}Z)V\n'
	}
	// String append needs a header and at least one truncation byte when overfull.
	for length in [4052, 4053] {
		body += 'const/16 v0, ${length}\nconst/16 v1, 0x61\ninvoke-static {v0, v1}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v0\nconst/4 v1, 3\nnew-array v1, v1, [Ljava/lang/Object;\nconst/4 v2, 0\naput-object v0, v1, v2\nconst-string v0, ""\nconst/4 v2, 1\naput-object v0, v1, v2\nconst/4 v2, 2\naput-object p0, v1, v2\n'
		body += if length == 4052 { 'invoke-static {v1}, ${main_type}->reject([Ljava/lang/Object;)V\n' } else { 'const/4 v2, -5\ninvoke-static {v1, v2}, ${main_type}->status([Ljava/lang/Object;I)V\n' }
	}
	// Fixed Long/Float need nine/five bytes. Null is a truncatable "NULL" string.
	for kind in ['long', 'null', 'float'] {
		last_reached := match kind {
			'long' { 4048 }
			'null' { 4051 } // One truncation byte remains, so the invalid item is reached.
			else { 4052 }
		}
		for length in [last_reached, last_reached + 1] {
			body += 'const/16 v0, ${length}\nconst/16 v1, 0x61\ninvoke-static {v0, v1}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v0\nconst/4 v1, 3\nnew-array v1, v1, [Ljava/lang/Object;\nconst/4 v2, 0\naput-object v0, v1, v2\n' +
				value_source(kind, 2) + 'const/4 v4, 1\naput-object v2, v1, v4\nconst/4 v4, 2\naput-object p0, v1, v4\n'
			body += if length == last_reached { 'invoke-static {v1}, ${main_type}->reject([Ljava/lang/Object;)V\n' } else { 'const/4 v2, -5\ninvoke-static {v1, v2}, ${main_type}->status([Ljava/lang/Object;I)V\n' }
		}
	}
	body += 'return-void'
	return method('private static sizes(${poison_type})V', 6, body)
}

fn utf_source() string {
	mut body := ''
	// Explicit char[] construction preserves embedded zero and isolated surrogates.
	// Each pair straddles 4052/4053 prepared bytes before int + invalid payload.
	for unit, prefix in {0x7f: 4051, 0: 4050, 0x80: 4050, 0x7ff: 4050,
		0x800: 4049, 0xd800: 4049, 0xdc00: 4049} {
		for overflow in [false, true] {
			body += 'const/16 v0, ${prefix + if overflow { 1 } else { 0 }}\nconst/16 v1, 0x61\ninvoke-static {v0, v1}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v0\n' +
				'const/4 v1, 1\nconst v2, ${unit}\ninvoke-static {v1, v2}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v1\n' +
				'invoke-virtual {v0, v1}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\nconst/4 v1, ${if overflow { 1 } else { 0 }}\ninvoke-static {v0, p0, v1}, ${main_type}->boundary(Ljava/lang/String;${poison_type}Z)V\n'
		}
	}
	// API-28 ART's valid surrogate pair consumes four bytes, unlike isolated units.
	for prefix in [4048, 4049] {
		body += 'const/16 v0, ${prefix}\nconst/16 v1, 0x61\ninvoke-static {v0, v1}, ${main_type}->chars(II)Ljava/lang/String;\nmove-result-object v0\ninvoke-static {}, ${main_type}->pair()Ljava/lang/String;\nmove-result-object v1\ninvoke-virtual {v0, v1}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\nconst/4 v1, ${if prefix == 4048 { 0 } else { 1 }}\ninvoke-static {v0, p0, v1}, ${main_type}->boundary(Ljava/lang/String;${poison_type}Z)V\n'
	}
	body += 'return-void'
	return method('private static utf(${poison_type})V', 3, body)
}

fn poison_source() string {
	return '.class public final ${poison_type}\n.super Ljava/lang/Object;\n.field public static calls:I\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public toString()Ljava/lang/String;', 2, '
sget v0, ${poison_type}->calls:I
add-int/lit8 v0, v0, 1
sput v0, ${poison_type}->calls:I
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "unsupported EventLog values must never be stringified"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
}

fn fixture_sources() map[string]string {
	return {
		'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		helpers_source() + shape_source() + chars_source() + scalars_source() + lists_source() + prefix_source() +
		boundary_source() + size_source() + utf_source() +
		method('private static run()V', 4, '
invoke-static {}, ${main_type}->shapes()V
invoke-static {}, ${main_type}->scalars()V
new-instance v0, ${poison_type}
invoke-direct {v0}, ${poison_type}-><init>()V
invoke-static {v0}, ${main_type}->lists(${poison_type})V
invoke-static {v0}, ${main_type}->prefix(${poison_type})V
invoke-static {v0}, ${main_type}->sizes(${poison_type})V
invoke-static {v0}, ${main_type}->utf(${poison_type})V
sget v1, ${poison_type}->calls:I
const/4 v2, 0
const-string v3, "valid ignored or invalid payloads must not invoke Object.toString"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {}, ${main_type}->run()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "EventLog validation and unavailable-backend status passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2
.catchall {:try_start .. :try_end} :failed')
		'org/vinix/bootstrap/Poison.smali': poison_source()
	}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/Poison.smali']
}

fn verify_source_references(source string) {
	assert source.starts_with('.class public final Lorg/vinix/bootstrap/'), 'fixture app classes only'
	if source.starts_with('.class public final ${poison_type}') {
		assert source.contains('->calls:I') && source.contains('toString()Ljava/lang/String;')
		assert source.contains('unsupported EventLog values must never be stringified')
		return
	}
	assert source.starts_with('.class public final ${main_type}'), 'exact Main class required'
	for descriptor in ['II', 'IJ', 'IF', 'ILjava/lang/String;', 'I[Ljava/lang/Object;'] {
		assert source.contains('${event_type}->writeEvent(${descriptor})I'), 'missing actual EventLog overload: ' + descriptor
	}
	for reference in ['Ljava/lang/reflect/Method;->isVarArgs()Z', '"Invalid payload item type"',
		'${main_type}->reject(', '${main_type}->unchanged(', '${main_type}->boundary(',
		'${main_type}->chars(II)', '${main_type}->pair()', 'const-wide v1, 0x100000001L',
		'Ljava/lang/String;-><init>([C)V', 'Ljava/lang/Float;->valueOf(F)',
		'Ljava/lang/Double;->valueOf(D)', '${poison_type}->calls:I'] {
		assert source.contains(reference), 'missing fixture contract reference: ' + reference
	}
	assert source.contains('"vinix-使用-Δ"')
		|| source.to_lower().contains('"vinix-\\u4f7f\\u7528-\\u0394"'), 'Unicode scalar control missing'
	assert source.contains('0xff') || source.contains('255'), 'first255 boundary required'
	assert !source.contains('->getBytes(') && !source.contains('->readEvents('), 'fixture must not use a replacement encoder/store oracle'
}
