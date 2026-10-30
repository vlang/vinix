// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated assertions for the production provider; copied beside that provider
// by image-bounds-source-check.v to avoid importing the complete build module.
module main

import androidtools
import os

fn methods(source string) map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		signature := block.all_before('\n').all_after_last(' ')
		assert signature !in result && block.contains('.end method'), signature
		result[signature] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn norm(text string) string {
	return text.split_into_lines().map(it.trim_space()).filter(it != '').join('\n')
}

fn verify_delta(old string, patched string) {
	before, after := methods(old), methods(patched)
	changed := ['<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V', 'setMaxWidth(I)V', 'setMaxHeight(I)V']
	added := ['getMaxWidth()I', 'getMaxHeight()I']
	assert before.len == 30 && after.len == 32
	mut left, right := old, patched
	for signature, body in before {
		assert signature in after, signature
		if signature in changed {
			assert body != after[signature] && body.all_before('\n') == after[signature].all_before('\n'), signature
			left = left.replace(body, 'CHANGED:' + signature)
			right = right.replace(after[signature], 'CHANGED:' + signature)
		} else { assert body == after[signature], signature }
	}
	for signature in added {
		assert signature !in before && signature in after
		right = right.replace(after[signature], '')
	}
	for axis in ['Width', 'Height'] {
		field := '.field private vinixMax' + axis + ':I'
		assert right.count(field) == 1
		right = right.replace(field, '')
		assert norm(after['getMax' + axis + '()I']) == '.method public getMax' + axis + '()I\n.registers 2\niget v0, p0, Landroid/widget/ImageView;->vinixMax' + axis + ':I\nreturn v0\n.end method'
		assert norm(after['setMax' + axis + '(I)V']) == '.method public setMax' + axis + '(I)V\n.registers 2\niput p1, p0, Landroid/widget/ImageView;->vinixMax' + axis + ':I\nreturn-void\n.end method'
	}
	assert norm(left) == norm(right), 'class metadata outside three methods/two fields changed'
	init := after[changed[0]]
	parent := 'invoke-direct {p0, p1, p2, p3, p4}, Landroid/view/View;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
	defaults := 'const v0, 0x7fffffff\niput v0, p0, Landroid/widget/ImageView;->vinixMaxWidth:I\niput v0, p0, Landroid/widget/ImageView;->vinixMaxHeight:I'
	xml := 'const/4 v1, 0x3\nconst v2, 0x7fffffff\ninvoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getDimensionPixelSize(II)I\nmove-result v1\ninvoke-virtual {p0, v1}, Landroid/widget/ImageView;->setMaxWidth(I)V\nconst/4 v1, 0x4\ninvoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getDimensionPixelSize(II)I\nmove-result v1\ninvoke-virtual {p0, v1}, Landroid/widget/ImageView;->setMaxHeight(I)V'
	assert norm(init).contains(parent + '\n' + defaults)
	assert norm(init).contains(xml + '\ninvoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V')
	assert norm(init).replace(defaults + '\n', '').replace(xml + '\n', '') == norm(before[changed[0]]), 'constructor bytes beyond insertions changed'
}

fn main() {
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		old := os.read_file(work + '/baseline-roundtrip/android/widget/ImageView.smali')!
		patched := os.read_file(work + '/patched-roundtrip/android/widget/ImageView.smali')!
		// DEX reorders new methods and canonicalizes register/constant spellings.
		assert methods(old).len == 30 && methods(patched).len == 32
		for signature in ['getMaxWidth()I', 'getMaxHeight()I', 'setMaxWidth(I)V', 'setMaxHeight(I)V'] {
			assert methods(patched)[signature].starts_with('.method public ' + signature + '\n')
		}
		assert patched.split_into_lines().filter(it.starts_with('.field ')).len == old.split_into_lines().filter(it.starts_with('.field ')).len + 2
		for signature, method in methods(old) {
			if signature !in ['<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V', 'setMaxWidth(I)V', 'setMaxHeight(I)V'] {
				assert methods(patched)[signature] == method, signature
			}
		}
		return
	}
	path := work + '/proof/android/widget/ImageView.smali'
	old := os.read_file(path)!
	patched := androidtools.framework_image_bounds_source(old)!
	verify_delta(old, patched)
	constructor := methods(old)['<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V']
	invalids := [patched,
		old.replace('.class public Landroid/widget/ImageView;', '.class public Lwrong/ImageView;'),
		old.replace('.super Landroid/view/View;', '.super Ljava/lang/Object;'),
		old.replace('.field private bitmap:', '.field public bitmap:'),
		old + '\n.field private unexpected:I\n',
		old.replace('.method public setMaxHeight(I)V', '.method public final setMaxHeight(I)V'),
		old.replace('.method public setMaxWidth(I)V', '.method public static setMaxWidth(I)V'),
		old.replace('setMaxHeight(I)V', 'missingMaxHeight(I)V'),
		old + '\n' + methods(old)['setMaxWidth(I)V'],
		old.replace(methods(old)['setMaxWidth(I)V'], '.method public setMaxWidth(I)V\n.registers 2\niput p1, p0, Landroid/widget/ImageView;->unexpected:I\nreturn-void\n.end method'),
		old.replace(constructor, constructor.replace('const/16 v0, 0x8', 'const/16 v0, 0x9')),
		old.replace(constructor, constructor.replace('    return-void', '    const-string v0, "unexpected side effect"\n    return-void')),
		old.replace('.method public constructor <init>(Landroid/content/Context;)V', '.method private constructor <init>(Landroid/content/Context;)V'),
		old + '\n.method public getMaxHeight()I\n.registers 2\nconst/4 v0, 0\nreturn v0\n.end method\n',
	]
	for invalid in invalids {
		assert invalid != old, 'negative mutation did not match baseline'
		os.write_file(path, invalid)!
		mut rejected := false
		androidtools.framework_image_bounds(work + '/proof') or { rejected = true }
		assert rejected && os.read_file(path)! == invalid, 'invalid input was accepted or mutated'
	}
	os.write_file(path, old)!
	androidtools.framework_image_bounds(work + '/proof')!
	assert os.read_file(path)! == patched
	println('IMAGE-BOUNDS-SOURCE-PASS changed=3 added=2 fields=2 malformed=' + invalids.len.str() + ' defaults-styled-properties unmodified-measurement')
}
