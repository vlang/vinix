// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn insets_method(signature string, locals int, body string) string {
	return '\n.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

// Insets are immutable values. Builders own mutable maps, and every build/copy
// clones those maps so later builder changes cannot alter a published snapshot.
// No system bar, keyboard or display cutout is supplied by the native backend.
fn framework_window_insets(smali string) ! {
	w := 'Landroid/view/WindowInsets;'
	b := 'Landroid/view/WindowInsets$Builder;'
	ins := 'Landroid/graphics/Insets;'
	mut text := '.class public final ' + w + '\n.super Ljava/lang/Object;\n' +
		'.field public static final CONSUMED:' + w + '\n' +
		'.field vinixTypes:[' + ins + '\n.field vinixMax:[' + ins + '\n.field vinixVisible:[Z\n' +
		'.field vinixConsumed:I\n.field vinixRound:Z\n'
	text += insets_method('static constructor <clinit>()V', 1,
		'new-instance v0, ' + w + '\ninvoke-direct {v0}, ' + w + '-><init>()V\nsput-object v0, ' + w + '->CONSUMED:' + w + '\nreturn-void')
	text += insets_method('public constructor <init>()V', 1,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nconst/16 v0, 10\nnew-array v0, v0, [' + ins + '\niput-object v0, p0, ' + w + '->vinixTypes:[' + ins +
			'\nconst/16 v0, 10\nnew-array v0, v0, [' + ins + '\niput-object v0, p0, ' + w + '->vinixMax:[' + ins +
			'\nconst/16 v0, 10\nnew-array v0, v0, [Z\niput-object v0, p0, ' + w + '->vinixVisible:[Z\nconst/4 v0, 7\niput v0, p0, ' + w + '->vinixConsumed:I\nreturn-void')
	mut copy := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
	for field, typ in {
		'vinixTypes':   '[' + ins
		'vinixMax':     '[' + ins
		'vinixVisible': '[Z'
	} {
		copy += 'iget-object v0, p1, ' + w + '->' + field + ':' + typ + '\ninvoke-virtual {v0}, ' + typ + '->clone()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ' + typ + '\niput-object v0, p0, ' + w + '->' + field + ':' + typ + '\n'
	}
	for field, typ in {
		'vinixConsumed': 'I'
		'vinixRound':    'Z'
	} {
		op := if typ == 'Z' { '-boolean' } else { '' }
		copy += 'iget' + op + ' v0, p1, ' + w + '->' + field + ':' + typ + '\niput' + op + ' v0, p0, ' + w + '->' + field + ':' + typ + '\n'
	}
	text += insets_method('public constructor <init>(' + w + ')V', 1, copy + 'return-void')
	// Entries overlap: unions use component-wise maxima, never sums.
	text += insets_method('static vinixGet([' + ins + 'I)' + ins, 5,
		'const/4 v0, 0\nconst/4 v1, 0\n:loop\nconst/16 v2, 10\nif-ge v1, v2, :done\nconst/4 v2, 1\nshl-int/2addr v2, v1\nand-int/2addr v2, p1\nif-eqz v2, :next\naget-object v3, p0, v1\nif-eqz v3, :next\nif-nez v0, :merge\nmove-object v0, v3\ngoto :next\n:merge\ninvoke-static {v0, v3}, ' + ins + '->max(' + ins + ins + ')' + ins + '\nmove-result-object v0\n:next\nadd-int/lit8 v1, v1, 1\ngoto :loop\n:done\nif-nez v0, :result\nsget-object v0, ' + ins + '->NONE:' + ins + '\n:result\nreturn-object v0')
	text += insets_method('static vinixSet([' + ins + 'I' + ins + ')V', 3,
		'invoke-virtual {p2}, Ljava/lang/Object;->getClass()Ljava/lang/Class;\nconst/4 v0, 0\n:loop\nconst/16 v1, 10\nif-ge v0, v1, :done\nconst/4 v1, 1\nshl-int/2addr v1, v0\nand-int/2addr v1, p1\nif-eqz v1, :next\naput-object p2, p0, v0\n:next\nadd-int/lit8 v0, v0, 1\ngoto :loop\n:done\nreturn-void')
	for name, field in {
		'getInsets':                   'vinixTypes'
		'getInsetsIgnoringVisibility': 'vinixMax'
	} {
		check := if name == 'getInsetsIgnoringVisibility' {
			insets_ime_check('p1', false)
		} else {
			''
		}
		text += insets_method('public ' + name + '(I)' + ins, 2, check +
			'iget-object v0, p0, ' + w + '->' + field + ':[' + ins + '\ninvoke-static {v0, p1}, ' + w + '->vinixGet([' + ins + 'I)' + ins + '\nmove-result-object v0\nreturn-object v0')
	}
	text += insets_method('public isVisible(I)Z', 3,
		'const/4 v0, 0\n:loop\nconst/16 v1, 10\nif-ge v0, v1, :yes\nconst/4 v1, 1\nshl-int/2addr v1, v0\nand-int/2addr v1, p1\nif-eqz v1, :next\niget-object v2, p0, ' + w + '->vinixVisible:[Z\naget-boolean v1, v2, v0\nif-eqz v1, :no\n:next\nadd-int/lit8 v0, v0, 1\ngoto :loop\n:yes\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	for name, mask in {
		'getSystemWindowInsets':           519
		'getStableInsets':                 519
		'getSystemGestureInsets':          16
		'getMandatorySystemGestureInsets': 32
		'getTappableElementInsets':        64
	} {
		getter := if name == 'getStableInsets' {
			'getInsetsIgnoringVisibility'
		} else {
			'getInsets'
		}
		text += insets_method('public ' + name + '()' + ins, 1,
			'const/16 v0, ' + mask.str() + '\ninvoke-virtual {p0, v0}, ' + w + '->' + getter + '(I)' + ins + '\nmove-result-object v0\nreturn-object v0')
	}
	for prefix, getter in {
		'SystemWindow': 'getSystemWindowInsets'
		'Stable':       'getStableInsets'
	} {
		for edge in ['Left', 'Top', 'Right', 'Bottom'] {
			text += insets_method('public get' + prefix + 'Inset' + edge + '()I', 1,
				'invoke-virtual {p0}, ' + w + '->' + getter + '()' + ins + '\nmove-result-object v0\niget v0, v0, ' + ins + '->' + edge.to_lower() + ':I\nreturn v0')
		}
	}
	text += insets_method('public getDisplayCutout()Landroid/view/DisplayCutout;', 1, 'const/4 v0, 0\nreturn-object v0')
	text += insets_method('public isRound()Z', 1, 'iget-boolean v0, p0, ' + w + '->vinixRound:Z\nreturn v0')
	text += insets_method('public isConsumed()Z', 2,
		'iget v0, p0, ' + w + '->vinixConsumed:I\nconst/4 v1, 7\nif-ne v0, v1, :no\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	for name, getter in {
		'hasSystemWindowInsets': 'getSystemWindowInsets'
		'hasStableInsets':       'getStableInsets'
	} {
		text += insets_method('public ' + name + '()Z', 2,
			'invoke-virtual {p0}, ' + w + '->' + getter + '()' + ins + '\nmove-result-object v0\nsget-object v1, ' + ins + '->NONE:' + ins + '\ninvoke-virtual {v0, v1}, ' + ins + '->equals(Ljava/lang/Object;)Z\nmove-result v0\nxor-int/lit8 v0, v0, 1\nreturn v0')
	}
	mut has := 'const/4 v2, -1\nsget-object v1, ' + ins + '->NONE:' + ins + '\n'
	for field in ['vinixTypes', 'vinixMax'] {
		has += 'iget-object v0, p0, ' + w + '->' + field + ':[' + ins + '\ninvoke-static {v0, v2}, ' + w + '->vinixGet([' + ins + 'I)' + ins + '\nmove-result-object v0\ninvoke-virtual {v0, v1}, ' + ins + '->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :yes\n'
	}
	text += insets_method('public hasInsets()Z', 3, has + 'const/4 v0, 0\nreturn v0\n:yes\nconst/4 v0, 1\nreturn v0')
	// API 30+ stable consumption is a no-op. System consumption clears both maps.
	text += insets_method('public consumeStableInsets()' + w, 0, 'return-object p0')
	text += insets_method('public consumeDisplayCutout()' + w, 2,
		'new-instance v0, ' + w + '\ninvoke-direct {v0, p0}, ' + w + '-><init>(' + w + ')V\niget v1, v0, ' + w + '->vinixConsumed:I\nor-int/lit8 v1, v1, 4\niput v1, v0, ' + w + '->vinixConsumed:I\nreturn-object v0')
	text += insets_method('public consumeSystemWindowInsets()' + w, 2,
		'new-instance v0, ' + w + '\ninvoke-direct {v0, p0}, ' + w + '-><init>(' + w + ')V\nconst/16 v1, 10\nnew-array v1, v1, [' + ins + '\niput-object v1, v0, ' + w + '->vinixTypes:[' + ins + '\nconst/16 v1, 10\nnew-array v1, v1, [' + ins + '\niput-object v1, v0, ' + w + '->vinixMax:[' + ins + '\niget v1, v0, ' + w + '->vinixConsumed:I\nor-int/lit8 v1, v1, 3\niput v1, v0, ' + w + '->vinixConsumed:I\nreturn-object v0')
	text += insets_method('public replaceSystemWindowInsets(IIII)' + w, 2,
		'iget v0, p0, ' + w + '->vinixConsumed:I\nand-int/lit8 v0, v0, 1\nif-eqz v0, :replace\nreturn-object p0\n:replace\ninvoke-static {p1, p2, p3, p4}, ' + ins + '->of(IIII)' + ins + '\nmove-result-object v0\nnew-instance v1, ' + b + '\ninvoke-direct {v1, p0}, ' + b + '-><init>(' + w + ')V\ninvoke-virtual {v1, v0}, ' + b + '->setSystemWindowInsets(' + ins + ')' + b + '\ninvoke-virtual {v1}, ' + b + '->build()' + w + '\nmove-result-object v0\nreturn-object v0')
	// Both maps are inset independently; negative amounts are rejected, and
	// subtraction clamps each edge at zero without changing the source snapshot.
	mut inset_map := 'const/4 v0, 0\nconst/4 v2, 0\n:loop\nconst/16 v1, 10\nif-ge v0, v1, :done\naget-object v3, p0, v0\nif-eqz v3, :next\n'
	for i, edge in ['left', 'top', 'right', 'bottom'] {
		reg := 'v' + (i + 4).str()
		inset_map += 'iget ' + reg + ', v3, ' + ins + '->' + edge + ':I\nsub-int/2addr ' + reg + ', p' + (i + 1).str() + '\ninvoke-static {' + reg + ', v2}, Ljava/lang/Math;->max(II)I\nmove-result ' + reg + '\n'
	}
	inset_map += 'invoke-static {v4, v5, v6, v7}, ' + ins + '->of(IIII)' + ins + '\nmove-result-object v3\naput-object v3, p0, v0\n:next\nadd-int/lit8 v0, v0, 1\ngoto :loop\n:done\nreturn-void'
	text += insets_method('static vinixInset([' + ins + 'IIII)V', 8, inset_map)
	text += insets_method('public inset(IIII)' + w, 2,
		'if-ltz p1, :negative\nif-ltz p2, :negative\nif-ltz p3, :negative\nif-ltz p4, :negative\nnew-instance v0, ' + w + '\ninvoke-direct {v0, p0}, ' + w + '-><init>(' + w + ')V\niget-object v1, v0, ' + w + '->vinixTypes:[' + ins + '\ninvoke-static {v1, p1, p2, p3, p4}, ' + w + '->vinixInset([' + ins + 'IIII)V\niget-object v1, v0, ' + w + '->vinixMax:[' + ins + '\ninvoke-static {v1, p1, p2, p3, p4}, ' + w + '->vinixInset([' + ins + 'IIII)V\nreturn-object v0\n:negative\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "Inset amounts must be nonnegative"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0')
	for name in ['inset', 'replaceSystemWindowInsets'] {
		for arg in if name == 'inset' {
			['Landroid/graphics/Rect;', ins]
		} else {
			['Landroid/graphics/Rect;']
		} {
			mut body := ''
			for i, edge in ['left', 'top', 'right', 'bottom'] {
				body += 'iget v' + i.str() + ', p1, ' + arg + '->' + edge + ':I\n'
			}
			body += 'invoke-virtual {p0, v0, v1, v2, v3}, ' + w + '->' + name + '(IIII)' + w + '\nmove-result-object v0\nreturn-object v0'
			text += insets_method('public ' + name + '(' + arg + ')' + w, 4, body)
		}
	}
	mut equal := 'if-eq p0, p1, :yes\ninstance-of v0, p1, ' + w + '\nif-eqz v0, :no\ncheck-cast p1, ' + w + '\n'
	mut hash := 'const/4 v0, 1\n'
	for field, typ in {
		'vinixTypes':   '[' + ins
		'vinixMax':     '[' + ins
		'vinixVisible': '[Z'
	} {
		array_type := if typ == '[Z' { '[Z' } else { '[Ljava/lang/Object;' }
		equal += 'iget-object v0, p0, ' + w + '->' + field + ':' + typ + '\niget-object v1, p1, ' + w + '->' + field + ':' + typ + '\ninvoke-static {v0, v1}, Ljava/util/Arrays;->equals(' + array_type + array_type + ')Z\nmove-result v0\nif-eqz v0, :no\n'
		hash += 'iget-object v1, p0, ' + w + '->' + field + ':' + typ + '\ninvoke-static {v1}, Ljava/util/Arrays;->hashCode(' + array_type + ')I\nmove-result v1\nmul-int/lit8 v0, v0, 31\nadd-int/2addr v0, v1\n'
	}
	for field, typ in {
		'vinixConsumed': 'I'
		'vinixRound':    'Z'
	} {
		op := if typ == 'Z' { '-boolean' } else { '' }
		equal += 'iget' + op + ' v0, p0, ' + w + '->' + field + ':' + typ + '\niget' + op + ' v1, p1, ' + w + '->' + field + ':' + typ + '\nif-ne v0, v1, :no\n'
		hash += 'iget' + op + ' v1, p0, ' + w + '->' + field + ':' + typ + '\nmul-int/lit8 v0, v0, 31\nadd-int/2addr v0, v1\n'
	}
	text += insets_method('public equals(Ljava/lang/Object;)Z', 2, equal + ':yes\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	text += insets_method('public hashCode()I', 2, hash + 'return v0')
	os.write_file(smali + '/android/view/WindowInsets.smali', text)!

	mut builder := '.class public final ' + b + '\n.super Ljava/lang/Object;\n.field private value:' + w + '\n'
	builder += insets_method('public constructor <init>()V', 1,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, ' + w + '\ninvoke-direct {v0}, ' + w + '-><init>()V\niput-object v0, p0, ' + b + '->value:' + w + '\nreturn-void')
	builder += insets_method('public constructor <init>(' + w + ')V', 1,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, ' + w + '\ninvoke-direct {v0, p1}, ' + w + '-><init>(' + w + ')V\niput-object v0, p0, ' + b + '->value:' + w + '\nreturn-void')
	builder += insets_method('public build()' + w, 2,
		'iget-object v1, p0, ' + b + '->value:' + w + '\nnew-instance v0, ' + w + '\ninvoke-direct {v0, v1}, ' + w + '-><init>(' + w + ')V\niget v1, v0, ' + w + '->vinixConsumed:I\nand-int/lit8 v1, v1, 1\nif-eqz v1, :published\nconst/16 v1, 10\nnew-array v1, v1, [' + ins + '\niput-object v1, v0, ' + w + '->vinixTypes:[' + ins + '\n:published\nreturn-object v0')
	for name, field in {
		'setInsets':                   'vinixTypes'
		'setInsetsIgnoringVisibility': 'vinixMax'
	} {
		check := if name == 'setInsetsIgnoringVisibility' {
			insets_ime_check('p1', true)
		} else {
			''
		}
		mask := if name == 'setInsets' { -2 } else { -3 }
		builder += insets_method('public ' + name + '(I' + ins + ')' + b, 3, check +
			'iget-object v0, p0, ' + b + '->value:' + w + '\niget-object v1, v0, ' + w + '->' + field + ':[' + ins + '\ninvoke-static {v1, p1, p2}, ' + w + '->vinixSet([' + ins + 'I' + ins + ')V\niget v2, v0, ' + w + '->vinixConsumed:I\nand-int/lit8 v2, v2, ' + mask.str() + '\niput v2, v0, ' + w + '->vinixConsumed:I\nreturn-object p0')
	}
	for name, field in {
		'setSystemWindowInsets': 'vinixTypes'
		'setStableInsets':       'vinixMax'
	} {
		mask := if name == 'setSystemWindowInsets' { -2 } else { -3 }
		builder += insets_method('public ' + name + '(' + ins + ')' + b, 7,
			'iget-object v0, p0, ' + b + '->value:' + w + '\niget-object v1, v0, ' + w + '->' + field + ':[' + ins +
				'\nconst/4 v2, 0\niget v3, p1, ' + ins + '->top:I\ninvoke-static {v2, v3, v2, v2}, ' + ins + '->of(IIII)' + ins + '\nmove-result-object v3\naput-object v3, v1, v2\n' +
				'iget v3, p1, ' + ins + '->left:I\niget v4, p1, ' + ins + '->right:I\niget v5, p1, ' + ins + '->bottom:I\ninvoke-static {v3, v2, v4, v5}, ' + ins + '->of(IIII)' + ins + '\nmove-result-object v3\nconst/4 v2, 1\naput-object v3, v1, v2\niget v2, v0, ' + w + '->vinixConsumed:I\nand-int/lit8 v2, v2, ' + mask.str() + '\niput v2, v0, ' + w + '->vinixConsumed:I\nreturn-object p0')
	}
	// These deprecated setters do not change the consumed flag in Android 15.
	// A system/typed setter must first make the current map non-consumed.
	for name, mask in {
		'setSystemGestureInsets':          16
		'setMandatorySystemGestureInsets': 32
		'setTappableElementInsets':        64
	} {
		builder += insets_method('public ' + name + '(' + ins + ')' + b, 2,
			'iget-object v0, p0, ' + b + '->value:' + w + '\niget-object v0, v0, ' + w + '->vinixTypes:[' + ins + '\nconst/16 v1, ' + mask.str() + '\ninvoke-static {v0, v1, p1}, ' + w + '->vinixSet([' + ins + 'I' + ins + ')V\nreturn-object p0')
	}
	builder += insets_method('public setVisible(IZ)' + b, 4,
		'iget-object v0, p0, ' + b + '->value:' + w + '\niget-object v0, v0, ' + w + '->vinixVisible:[Z\nconst/4 v1, 0\n:loop\nconst/16 v2, 10\nif-ge v1, v2, :done\nconst/4 v2, 1\nshl-int/2addr v2, v1\nand-int/2addr v2, p1\nif-eqz v2, :next\naput-boolean p2, v0, v1\n:next\nadd-int/lit8 v1, v1, 1\ngoto :loop\n:done\nreturn-object p0')
	builder += insets_method('public setRound(Z)' + b, 1,
		'iget-object v0, p0, ' + b + '->value:' + w + '\niput-boolean p1, v0, ' + w + '->vinixRound:Z\nreturn-object p0')
	os.write_file(smali + '/android/view/WindowInsets$Builder.smali', builder)!
}

fn insets_ime_check(reg string, exact bool) string {
	// Android 15's Builder rejects the IME-only mask; its getter rejects any
	// mask containing IME. Keep the two public methods' actual behavior.
	prefix := if exact {
		'const/16 v0, 8\nif-ne v0, ' + reg + ', :valid_mask\n'
	} else {
		'and-int/lit8 v0, ' + reg + ', 8\nif-eqz v0, :valid_mask\n'
	}
	return prefix + 'new-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "Maximum IME insets are unavailable"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid_mask\n'
}
