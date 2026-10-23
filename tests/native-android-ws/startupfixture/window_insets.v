// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

const insets_probe = 'Lorg/vinix/bootstrap/WindowInsetsProbe;'
const insets_value = 'Landroid/view/WindowInsets;'
const insets_builder = 'Landroid/view/WindowInsets$Builder;'
const insets_edges = 'Landroid/graphics/Insets;'

fn inset_sample(values []int) string {
	mut text := ''
	for i, value in values { text += 'const/16 v${i}, ${value}\n' }
	return text + 'invoke-static {v0, v1, v2, v3}, ${insets_edges}->of(IIII)${insets_edges}\nmove-result-object v4\n'
}

fn inset_expect(register string, values []int) string {
	mut text := ''
	for i, value in values { text += 'const/16 v${i + 1}, ${value}\n' }
	return text + 'invoke-static {${register}, v1, v2, v3, v4}, ${insets_probe}->values(${insets_edges}IIII)V\n'
}

fn inset_get(register string, name string, values []int) string {
	return 'invoke-virtual {${register}}, ${insets_value}->${name}()${insets_edges}\nmove-result-object v0\n' + inset_expect('v0', values)
}

fn inset_finish(message string) string {
	return 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn install_window_insets_probe(dir string) ! {
	w := insets_value
	b := insets_builder
	i := insets_edges
	c := insets_probe
	mut source := '.class public ${c}\n.super Ljava/lang/Object;\n'
	source += method('public static check()V', '
# The exact missing Maps class is the first operation for an unambiguous baseline.
new-instance v7, ${b}
invoke-direct {v7}, ${b}-><init>()V
invoke-virtual {v7}, ${b}->build()${w}
move-result-object v8
invoke-virtual {v8}, ${w}->isConsumed()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v8}, ${w}->hasInsets()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v8}, ${w}->isRound()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v8}, ${w}->getDisplayCutout()Landroid/view/DisplayCutout;
move-result-object v0
if-nez v0, :bad
const/16 v0, 7
invoke-virtual {v8, v0}, ${w}->isVisible(I)Z
move-result v0
if-nez v0, :bad
' + inset_get('v8', 'getSystemWindowInsets', [0, 0, 0, 0]) +
		inset_get('v8', 'getStableInsets', [0, 0, 0, 0]) + '
sget-object v8, ${w}->CONSUMED:${w}
invoke-virtual {v8}, ${w}->isConsumed()Z
move-result v0
if-eqz v0, :bad
invoke-static {}, ${c}->legacy()V
invoke-static {}, ${c}->typed()V
invoke-static {}, ${c}->negative()V
invoke-static {}, ${c}->consumedAndIme()V
invoke-static {}, ${c}->signedAndOverlays()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-WINDOW-INSETS-PASS defaults legacy-five typed-masks maxima visibility copy-build-isolation consume replacement inset-clamp negative-arguments signed-union system-overlays"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
' + inset_finish('WindowInsets default native state'))
	mut legacy := 'new-instance v7, ${b}\ninvoke-direct {v7}, ${b}-><init>()V\n'
	getters := ['SystemWindow', 'Stable', 'SystemGesture', 'MandatorySystemGesture', 'TappableElement']
	edges := [[3, 5, 7, 11], [13, 17, 19, 23], [2, 4, 6, 8], [1, 3, 5, 7], [4, 6, 8, 10]]
	for n, name in getters {
		legacy += inset_sample(edges[n]) + 'invoke-virtual {v7, v4}, ${b}->set${name}Insets(${i})${b}\nmove-result-object v0\nif-ne v0, v7, :bad\n'
	}
	legacy += 'invoke-virtual {v7}, ${b}->build()${w}\nmove-result-object v8\n'
	for n, name in getters { legacy += inset_get('v8', 'get' + name + 'Insets', edges[n]) }
	// Compat setters split status/navigation edges, but legacy getters preserve all four values.
	for n, name in ['SystemWindow', 'Stable'] {
		for e, edge in ['Left', 'Top', 'Right', 'Bottom'] {
			legacy += 'invoke-virtual {v8}, ${w}->get${name}Inset${edge}()I\nmove-result v0\nconst/16 v1, ${edges[n][e]}\nif-ne v0, v1, :bad\n'
		}
	}
	legacy += '
invoke-virtual {v8}, ${w}->isConsumed()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v8}, ${w}->hasSystemWindowInsets()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v8}, ${w}->hasStableInsets()Z
move-result v0
if-eqz v0, :bad
new-instance v6, ${w}
invoke-direct {v6, v8}, ${w}-><init>(${w})V
invoke-virtual {v6, v8}, ${w}->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v6}, ${w}->hashCode()I
move-result v0
invoke-virtual {v8}, ${w}->hashCode()I
move-result v1
if-ne v0, v1, :bad
new-instance v5, ${b}
invoke-direct {v5, v8}, ${b}-><init>(${w})V
' + inset_sample([31, 37, 41, 43]) + '
invoke-virtual {v7, v4}, ${b}->setSystemWindowInsets(${i})${b}
invoke-virtual {v5}, ${b}->build()${w}
move-result-object v9
' + inset_get('v8', 'getSystemWindowInsets', edges[0]) +
		inset_get('v6', 'getSystemWindowInsets', edges[0]) +
		inset_get('v9', 'getSystemWindowInsets', edges[0]) + '
invoke-virtual {v7}, ${b}->build()${w}
move-result-object v9
' + inset_get('v9', 'getSystemWindowInsets', [31, 37, 41, 43]) + '
# Consumption follows current Android: stable is a no-op; system clears both maps.
invoke-virtual {v8}, ${w}->consumeStableInsets()${w}
move-result-object v9
' + inset_get('v9', 'getStableInsets', edges[1]) + '
invoke-virtual {v8}, ${w}->consumeDisplayCutout()${w}
move-result-object v9
' + inset_get('v9', 'getSystemWindowInsets', edges[0]) + '
invoke-virtual {v8}, ${w}->consumeSystemWindowInsets()${w}
move-result-object v9
invoke-virtual {v9}, ${w}->isConsumed()Z
move-result v0
if-eqz v0, :bad
' + inset_get('v9', 'getSystemWindowInsets', [0, 0, 0, 0]) +
		inset_get('v9', 'getStableInsets', [0, 0, 0, 0]) +
		inset_get('v9', 'getSystemGestureInsets', [0, 0, 0, 0]) + '
const/16 v0, 9
invoke-virtual {v9, v0, v0, v0, v0}, ${w}->replaceSystemWindowInsets(IIII)${w}
move-result-object v9
' + inset_get('v9', 'getSystemWindowInsets', [0, 0, 0, 0]) + '
const/4 v0, 1
const/4 v1, 7
const/16 v2, 10
const/4 v3, 4
invoke-virtual {v8, v0, v1, v2, v3}, ${w}->inset(IIII)${w}
move-result-object v9
' + inset_get('v9', 'getSystemWindowInsets', [2, 0, 0, 7]) +
		inset_get('v9', 'getStableInsets', [12, 10, 9, 19]) +
		inset_get('v9', 'getSystemGestureInsets', [1, 0, 0, 4]) + '
new-instance v4, Landroid/graphics/Rect;
const/4 v0, 1
const/4 v1, 7
const/16 v2, 10
const/4 v3, 4
invoke-direct {v4, v0, v1, v2, v3}, Landroid/graphics/Rect;-><init>(IIII)V
invoke-virtual {v8, v4}, ${w}->inset(Landroid/graphics/Rect;)${w}
move-result-object v9
' + inset_get('v9', 'getStableInsets', [12, 10, 9, 19]) + '
const/16 v0, 9
const/16 v1, 10
const/16 v2, 11
const/16 v3, 12
invoke-virtual {v8, v0, v1, v2, v3}, ${w}->replaceSystemWindowInsets(IIII)${w}
move-result-object v9
' + inset_get('v9', 'getSystemWindowInsets', [9, 10, 11, 12]) +
		inset_get('v9', 'getStableInsets', edges[1]) + '
new-instance v4, Landroid/graphics/Rect;
const/4 v0, 2
const/4 v1, 4
const/4 v2, 6
const/16 v3, 8
invoke-direct {v4, v0, v1, v2, v3}, Landroid/graphics/Rect;-><init>(IIII)V
invoke-virtual {v8, v4}, ${w}->replaceSystemWindowInsets(Landroid/graphics/Rect;)${w}
move-result-object v9
' + inset_get('v9', 'getSystemWindowInsets', [2, 4, 6, 8]) +
		inset_get('v8', 'getSystemWindowInsets', edges[0]) + inset_finish('WindowInsets legacy values, snapshots, consumption or inset arithmetic')
	source += method('private static legacy()V', legacy)
	mut typed := 'new-instance v7, ${b}\ninvoke-direct {v7}, ${b}-><init>()V\n'
	for mask, values in {
		1:  [7, 2, 5, 13]
		2:  [1, 11, 9, 3]
		20: [6, 3, 8, 2]
	} {
		typed += inset_sample(values) + 'const/16 v0, ${mask}\ninvoke-virtual {v7, v0, v4}, ${b}->setInsets(I${i})${b}\nmove-result-object v0\nif-ne v0, v7, :bad\n'
	}
	typed += inset_sample([20, 21, 22, 23]) + '
const/4 v0, 3
invoke-virtual {v7, v0, v4}, ${b}->setInsetsIgnoringVisibility(I${i})${b}
move-result-object v0
if-ne v0, v7, :bad
const/4 v0, 1
const/4 v1, 1
invoke-virtual {v7, v0, v1}, ${b}->setVisible(IZ)${b}
move-result-object v0
if-ne v0, v7, :bad
invoke-virtual {v7}, ${b}->build()${w}
move-result-object v8
'
	for mask, values in {
		1:  [7, 2, 5, 13]
		2:  [1, 11, 9, 3]
		3:  [7, 11, 9, 13]
		4:  [6, 3, 8, 2]
		16: [6, 3, 8, 2]
	} {
		typed += 'const/16 v0, ${mask}\ninvoke-virtual {v8, v0}, ${w}->getInsets(I)${i}\nmove-result-object v0\n' + inset_expect('v0', values)
	}
	typed += '
const/4 v0, 3
invoke-virtual {v8, v0}, ${w}->getInsetsIgnoringVisibility(I)${i}
move-result-object v0
' + inset_expect('v0', [20, 21, 22, 23]) + '
const/4 v0, 1
invoke-virtual {v8, v0}, ${w}->isVisible(I)Z
move-result v0
if-eqz v0, :bad
const/4 v0, 3
invoke-virtual {v8, v0}, ${w}->isVisible(I)Z
move-result v0
if-nez v0, :bad
const/4 v0, 0
invoke-virtual {v8, v0}, ${w}->isVisible(I)Z
move-result v0
if-eqz v0, :bad
# Both original and copy-build snapshots own their visibility/maps.
new-instance v5, ${b}
invoke-direct {v5, v8}, ${b}-><init>(${w})V
const/4 v0, 1
const/4 v1, 0
invoke-virtual {v5, v0, v1}, ${b}->setVisible(IZ)${b}
invoke-virtual {v7, v0, v1}, ${b}->setVisible(IZ)${b}
invoke-virtual {v8, v0}, ${w}->isVisible(I)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v5}, ${b}->build()${w}
move-result-object v9
const/4 v0, 1
invoke-virtual {v9, v0}, ${w}->isVisible(I)Z
move-result v0
if-nez v0, :bad
' + inset_finish('WindowInsets typed masks, component maxima or visibility ownership')
	source += method('private static typed()V', typed)
	mut negative := 'new-instance v7, ${b}\ninvoke-direct {v7}, ${b}-><init>()V\ninvoke-virtual {v7}, ${b}->build()${w}\nmove-result-object v8\n'
	for n in 0 .. 4 {
		negative += 'const/4 v0, 0\nconst/4 v1, 0\nconst/4 v2, 0\nconst/4 v3, 0\nconst/4 v${n}, -1\n:try_${n}\ninvoke-virtual {v8, v0, v1, v2, v3}, ${w}->inset(IIII)${w}\n:try_end_${n}\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:try_${n} .. :try_end_${n}} :caught_${n}\n:caught_${n}\nmove-exception v0\n'
	}
	negative += 'const/16 v1, 8\n:try_max\ninvoke-virtual {v8, v1}, ${w}->getInsetsIgnoringVisibility(I)${i}\n:try_max_end\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:try_max .. :try_max_end} :caught_max\n:caught_max\nmove-exception v0\n' + inset_finish('WindowInsets invalid negative inset or IME maximum accepted')
	source += method('private static negative()V', negative)
	source += method('private static consumedAndIme()V', '
# Current AOSP legacy gesture setters retain the consumed flag: build discards that map.
new-instance v7, ${b}
invoke-direct {v7}, ${b}-><init>()V
' + inset_sample([5, 6, 7, 8]) + '
invoke-virtual {v7, v4}, ${b}->setSystemGestureInsets(${i})${b}
invoke-virtual {v7}, ${b}->build()${w}
move-result-object v8
invoke-virtual {v8}, ${w}->isConsumed()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v8}, ${w}->hasInsets()Z
move-result v0
if-nez v0, :bad
' + inset_get('v8', 'getSystemGestureInsets', [0, 0, 0, 0]) + '
# AOSP Builder rejects exactly IME, but accepts a mixed IME/status maximum map.
' + inset_sample([5, 6, 7, 8]) + '
const/16 v0, 9
invoke-virtual {v7, v0, v4}, ${b}->setInsetsIgnoringVisibility(I${i})${b}
sget-object v4, ${i}->NONE:${i}
const/4 v0, 1
invoke-virtual {v7, v0, v4}, ${b}->setInsetsIgnoringVisibility(I${i})${b}
invoke-virtual {v7}, ${b}->build()${w}
move-result-object v8
invoke-virtual {v8}, ${w}->hasInsets()Z
move-result v0
if-eqz v0, :bad
const/4 v0, 1
invoke-virtual {v8, v0}, ${w}->getInsetsIgnoringVisibility(I)${i}
move-result-object v0
' + inset_expect('v0', [0, 0, 0, 0]) + '
const/16 v1, 9
:try_mixed
invoke-virtual {v8, v1}, ${w}->getInsetsIgnoringVisibility(I)${i}
:try_mixed_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:try_mixed .. :try_mixed_end} :caught_mixed
:caught_mixed
move-exception v0
const/16 v1, 8
sget-object v4, ${i}->NONE:${i}
:try_builder_ime
invoke-virtual {v7, v1, v4}, ${b}->setInsetsIgnoringVisibility(I${i})${b}
:try_builder_ime_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:try_builder_ime .. :try_builder_ime_end} :caught_builder_ime
:caught_builder_ime
move-exception v0
' + inset_finish('WindowInsets legacy consumed flag or mixed IME maximum semantics'))
	mut signed := 'new-instance v7, ${b}\ninvoke-direct {v7}, ${b}-><init>()V\n'
	for mask, signed_edges in {
		1: [-7, -2, -5, -13]
		2: [-1, -11, -9, -3]
	} {
		signed += inset_sample(signed_edges) + 'const/16 v0, ${mask}\ninvoke-virtual {v7, v0, v4}, ${b}->setInsets(I${i})${b}\n'
	}
	for mask, signed_edges in {
		1: [-40, -60, -80, -100]
		2: [-70, -20, -50, -30]
	} {
		signed += inset_sample(signed_edges) + 'const/16 v0, ${mask}\ninvoke-virtual {v7, v0, v4}, ${b}->setInsetsIgnoringVisibility(I${i})${b}\n'
	}
	signed += 'invoke-virtual {v7}, ${b}->build()${w}\nmove-result-object v8\n'
	// An absent selected entry does not contribute zero to a populated signed union.
	for mask, signed_edges in {
		0: [0, 0, 0, 0]
		1: [-7, -2, -5, -13]
		2: [-1, -11, -9, -3]
		3: [-1, -2, -5, -3]
		5: [-7, -2, -5, -13]
	} {
		signed += 'const/16 v0, ${mask}\ninvoke-virtual {v8, v0}, ${w}->getInsets(I)${i}\nmove-result-object v0\n' + inset_expect('v0', signed_edges)
	}
	for mask, signed_edges in {
		1: [-40, -60, -80, -100]
		3: [-40, -20, -50, -30]
		5: [-40, -60, -80, -100]
	} {
		signed += 'const/16 v0, ${mask}\ninvoke-virtual {v8, v0}, ${w}->getInsetsIgnoringVisibility(I)${i}\nmove-result-object v0\n' + inset_expect('v0', signed_edges)
	}
	signed += inset_get('v8', 'getSystemWindowInsets', [-1, -2, -5, -3]) +
		inset_get('v8', 'getStableInsets', [-40, -20, -50, -30])
	// Type.systemBars includes systemOverlays (512) in current Android, including legacy signed_edges.
	signed += inset_sample([17, 19, 23, 29]) + 'const/16 v0, 512\ninvoke-virtual {v7, v0, v4}, ${b}->setInsets(I${i})${b}\n'
	signed += inset_sample([31, 37, 41, 43]) + 'const/16 v0, 512\ninvoke-virtual {v7, v0, v4}, ${b}->setInsetsIgnoringVisibility(I${i})${b}\ninvoke-virtual {v7}, ${b}->build()${w}\nmove-result-object v9\n'
	for n, name in ['SystemWindow', 'Stable'] {
		signed_edges := if n == 0 { [17, 19, 23, 29] } else { [31, 37, 41, 43] }
		signed += inset_get('v9', 'get' + name + 'Insets', signed_edges)
		for e, edge in ['Left', 'Top', 'Right', 'Bottom'] {
			signed += 'invoke-virtual {v9}, ${w}->get${name}Inset${edge}()I\nmove-result v0\nconst/16 v1, ${signed_edges[e]}\nif-ne v0, v1, :bad\n'
		}
	}
	// The earlier immutable build still owns its signed values after overlay assignment.
	signed += inset_get('v8', 'getSystemWindowInsets', [-1, -2, -5, -3]) +
		inset_get('v8', 'getStableInsets', [-40, -20, -50, -30]) +
		inset_finish('WindowInsets signed union or systemOverlays legacy signed_edges')
	source += method('private static signedAndOverlays()V', signed)
	mut values := ''
	for n, edge in ['left', 'top', 'right', 'bottom'] {
		values += 'iget v0, p0, ${i}->${edge}:I\nif-ne v0, p${n + 1}, :bad\n'
	}
	source += method('private static values(${i}IIII)V', values + inset_finish('WindowInsets exact four-edge value'))
	os.write_file(dir + '/WindowInsetsProbe.smali', source)!
}
