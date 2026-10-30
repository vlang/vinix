// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import crypto.sha256
import os

fn image_bounds_method(source string, header string) !string {
	mut found := ''
	for block in source.split('.method ')[1..] {
		if block.all_before('\n').all_after_last(' ') != header.all_after_last(' ') { continue }
		if found != '' || block.all_before('\n') != header {
			return error('unique ImageView method header required: ' + header)
		}
		end := block.index('.end method') or { return error('unterminated ImageView method') }
		found = '.method ' + block[..end + '.end method'.len]
	}
	if found == '' { return error('missing ImageView method: ' + header) }
	return found
}

fn image_bounds_normalize(source string) string {
	return source.split_into_lines().map(it.trim_space()).filter(it != '').join('\n')
}

// ImageView's native measurement path is preserved. These are the Java-facing
// maximum-size properties, including constructor defaults and styled values.
// AOSP's max setters retain the supplied integer without requesting layout.
pub fn framework_image_bounds_source(original string) !string {
	if original.split_into_lines().filter(it.starts_with('.class ')) != ['.class public Landroid/widget/ImageView;']
		|| original.split_into_lines().filter(it.starts_with('.super ')) != ['.super Landroid/view/View;']
		|| original.split_into_lines().filter(it.starts_with('.field ')) != [
			'.field private bitmap:Landroid/graphics/Bitmap;',
			'.field private colorFilter:Landroid/graphics/ColorFilter;',
			'.field private drawable:Landroid/graphics/drawable/Drawable;',
			'.field private scaleType:Landroid/widget/ImageView$ScaleType;',
			'.field private final scaletype_from_int:[Landroid/widget/ImageView$ScaleType;',
		] {
		return error('canonical ImageView class and field schema required')
	}
	mut headers := original.split_into_lines().filter(it.starts_with('.method ')).map(it.all_after('.method '))
	headers.sort()
	mut expected := image_bounds_headers.clone()
	expected.sort()
	if headers != expected || original.count('.end method') != headers.len {
		return error('canonical ImageView method schema required')
	}
	for header in expected { image_bounds_method(original, header)! }
	for axis in ['Width', 'Height'] {
		header := 'public setMax' + axis + '(I)V'
		if image_bounds_normalize(image_bounds_method(original, header)!) != '.method ' + header + '\n.registers 2\nreturn-void\n.end method' {
			return error('retained ImageView maximum setter stub required')
		}
	}
	for signature, body in {
		'<init>(Landroid/content/Context;)V': 'invoke-direct {p0, p1, v0}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V'
		'<init>(Landroid/content/Context;Landroid/util/AttributeSet;)V': 'invoke-direct {p0, p1, p2, v0}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V'
		'<init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V': 'invoke-direct {p0, p1, p2, p3, v0}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
	} {
		registers := if signature == '<init>(Landroid/content/Context;)V' { 3 } else if signature.ends_with('AttributeSet;)V') { 4 } else { 5 }
		wanted := '.method public constructor ' + signature + '\n.registers ' + registers.str() + '\nconst/4 v0, 0x0\n' + body + '\nreturn-void\n.end method'
		if image_bounds_normalize(image_bounds_method(original, 'public constructor ' + signature)!) != wanted {
			return error('retained ImageView constructor delegation required')
		}
	}
	header := 'public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
	constructor := image_bounds_method(original, header)!
	// Pin the complete normalized constructor before inserting into its two
	// known straight-line locations; unknown callbacks or control flow fail shut.
	constructor_sha := sha256.sum(image_bounds_normalize(constructor).bytes()).hex()
	if constructor_sha != 'd45633559aad4d0facc94667625159a558d99f8ad7694a973ba7379e24a78bdc' {
		return error('retained ImageView constructor required: ' + constructor_sha)
	}
	parent := 'invoke-direct {p0, p1, p2, p3, p4}, Landroid/view/View;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
	recycle := 'invoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V'
	if constructor.count(parent) != 1 || constructor.count(recycle) != 1 {
		return error('unique ImageView constructor insertion points required')
	}
	mut changed := constructor.replace(parent, parent + '\nconst v0, 0x7fffffff\niput v0, p0, Landroid/widget/ImageView;->vinixMaxWidth:I\niput v0, p0, Landroid/widget/ImageView;->vinixMaxHeight:I')
	changed = changed.replace(recycle, 'const/4 v1, 0x3\nconst v2, 0x7fffffff\ninvoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getDimensionPixelSize(II)I\nmove-result v1\ninvoke-virtual {p0, v1}, Landroid/widget/ImageView;->setMaxWidth(I)V\nconst/4 v1, 0x4\ninvoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getDimensionPixelSize(II)I\nmove-result v1\ninvoke-virtual {p0, v1}, Landroid/widget/ImageView;->setMaxHeight(I)V\n' + recycle)
	mut source := original.replace(constructor, changed)
	source += '\n.field private vinixMaxWidth:I\n.field private vinixMaxHeight:I\n'
	for axis in ['Width', 'Height'] {
		header_set := 'public setMax' + axis + '(I)V'
		old := image_bounds_method(source, header_set)!
		source = source.replace(old, '.method ' + header_set + '\n.registers 2\niput p1, p0, Landroid/widget/ImageView;->vinixMax' + axis + ':I\nreturn-void\n.end method')
		source += '\n.method public getMax' + axis + '()I\n.registers 2\niget v0, p0, Landroid/widget/ImageView;->vinixMax' + axis + ':I\nreturn v0\n.end method\n'
	}
	return source
}

pub fn framework_image_bounds(smali string) ! {
	path := smali + '/android/widget/ImageView.smali'
	patched := framework_image_bounds_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}

const image_bounds_headers = [
	'public constructor <init>(Landroid/content/Context;)V',
	'public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V',
	'public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V',
	'public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V',
	'public clearColorFilter()V', 'public getColorFilter()Landroid/graphics/ColorFilter;',
	'public getDrawable()Landroid/graphics/drawable/Drawable;', 'public getImageMatrix()Landroid/graphics/Matrix;',
	'public getImageTintList()Landroid/content/res/ColorStateList;', 'public getImageTintMode()Landroid/graphics/PorterDuff$Mode;',
	'public getScaleType()Landroid/widget/ImageView$ScaleType;',
	'protected native native_constructor(Landroid/content/Context;Landroid/util/AttributeSet;)J',
	'protected native native_setDrawable(JJ)V', 'protected native native_setScaleType(JI)V',
	'public setAdjustViewBounds(Z)V', 'public setColorFilter(I)V',
	'public setColorFilter(ILandroid/graphics/PorterDuff$Mode;)V', 'public setColorFilter(Landroid/graphics/ColorFilter;)V',
	'public setCropToPadding(Z)V', 'public setImageAlpha(I)V', 'public setImageBitmap(Landroid/graphics/Bitmap;)V',
	'public setImageDrawable(Landroid/graphics/drawable/Drawable;)V', 'public setImageMatrix(Landroid/graphics/Matrix;)V',
	'public setImageResource(I)V', 'public setImageState([IZ)V',
	'public setImageTintList(Landroid/content/res/ColorStateList;)V', 'public setImageTintMode(Landroid/graphics/PorterDuff$Mode;)V',
	'public setMaxHeight(I)V', 'public setMaxWidth(I)V', 'public setScaleType(Landroid/widget/ImageView$ScaleType;)V',
]
