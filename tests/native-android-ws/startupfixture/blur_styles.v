// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_blur_styles_probe(dir string) ! {
	style := 'Landroid/graphics/BlurMaskFilter$Blur;'
	probe := 'Lorg/vinix/bootstrap/BlurStylesProbe;'
	bad := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Blur enum names, native IDs, identity and array isolation"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	// Resolve the exact field that stopped Maps before testing the wider enum contract.
	mut check := 'sget-object v0, ${style}->OUTER:${style}\nif-eqz v0, :bad\n'
	for i, name in ['NORMAL', 'SOLID', 'OUTER', 'INNER'] {
		check += 'sget-object v0, ${style}->${name}:${style}\nconst-string v1, "${name}"\nconst/4 v2, ${i}\ninvoke-static {v0, v1, v2}, ${probe}->style(${style}Ljava/lang/String;I)V\n'
	}
	check += 'invoke-static {}, ${style}->values()[${style}\nmove-result-object v3\narray-length v0, v3\nconst/4 v1, 4\nif-ne v0, v1, :bad\n'
	for i, name in ['NORMAL', 'SOLID', 'OUTER', 'INNER'] {
		check += 'const/4 v0, ${i}\naget-object v1, v3, v0\nsget-object v2, ${style}->${name}:${style}\nif-ne v1, v2, :bad\n'
		for previous in 0 .. i {
			check += 'const/4 v0, ${previous}\naget-object v2, v3, v0\nif-eq v1, v2, :bad\n'
		}
	}
	check += 'invoke-static {}, ${style}->values()[${style}\nmove-result-object v4\nif-eq v3, v4, :bad\nconst/4 v0, 0\nconst/4 v1, 0\naput-object v1, v3, v0\naget-object v1, v4, v0\nsget-object v2, ${style}->NORMAL:${style}\nif-ne v1, v2, :bad\ninvoke-static {}, ${style}->values()[${style}\nmove-result-object v3\naget-object v1, v3, v0\nif-ne v1, v2, :bad\n'
	check += ':unknown_start\nconst-string v0, "outer"\ninvoke-static {v0}, ${style}->valueOf(Ljava/lang/String;)${style}\n:unknown_end\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:unknown_start .. :unknown_end} :unknown_caught\n:unknown_caught\nmove-exception v0\n'
	check += ':null_start\nconst/4 v0, 0\ninvoke-static {v0}, ${style}->valueOf(Ljava/lang/String;)${style}\n:null_end\ngoto :bad\n.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_caught\n:null_caught\nmove-exception v0\n'
	check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-BLUR-STYLES-PASS OUTER NORMAL-SOLID-OUTER-INNER names ordinals native-ids distinct-identities values-order clone-isolation valueOf-valid-unknown-null"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n' + bad
	helper := '
invoke-virtual {p0}, Ljava/lang/Enum;->name()Ljava/lang/String;
move-result-object v0
invoke-virtual {p1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Ljava/lang/Enum;->ordinal()I
move-result v0
if-ne v0, p2, :bad
invoke-virtual {p0}, Ljava/lang/Enum;->getDeclaringClass()Ljava/lang/Class;
move-result-object v0
const-class v1, ${style}
if-ne v0, v1, :bad
invoke-static {p1}, ${style}->valueOf(Ljava/lang/String;)${style}
move-result-object v0
if-ne v0, p0, :bad
invoke-static {v1, p1}, Ljava/lang/Enum;->valueOf(Ljava/lang/Class;Ljava/lang/String;)Ljava/lang/Enum;
move-result-object v0
if-ne v0, p0, :bad
const-string v0, "native_int"
invoke-virtual {v1, v0}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->getInt(Ljava/lang/Object;)I
move-result v1
if-ne v1, p2, :bad
invoke-virtual {v0}, Ljava/lang/reflect/Field;->getModifiers()I
move-result v0
and-int/lit8 v0, v0, 0x10
if-eqz v0, :bad
return-void
' + bad
	os.write_file(dir + '/BlurStylesProbe.smali', '.class public ${probe}\n.super Ljava/lang/Object;\n' +
		method('public static check()V', check) +
		method('private static style(${style}Ljava/lang/String;I)V', helper))!
}
