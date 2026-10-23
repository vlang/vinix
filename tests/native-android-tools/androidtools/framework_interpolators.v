// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// AnimationUtils must load the actual XML, including themed/referenced floats.
// The upstream ATL loader returned null and its PathInterpolator was linear.
// Formulas and XML contracts follow AOSP android.view.animation interpolators.
fn framework_interpolators(smali string) ! {
	utils := smali + '/android/view/animation/AnimationUtils.smali'
	mut text := os.read_file(utils)!
	text = framework_replace_method(text,
		'loadInterpolator(Landroid/content/Context;I)Landroid/view/animation/Interpolator;',
		time_animator_method('public static loadInterpolator(Landroid/content/Context;I)Landroid/view/animation/Interpolator;', 2, '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;
move-result-object v1
invoke-static {v0, v1, p1}, Landroid/view/animation/AnimationUtils;->loadInterpolator(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;I)Landroid/view/animation/Interpolator;
move-result-object v0
return-object v0'))!
	text = framework_replace_method(text,
		'loadInterpolator(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;I)Landroid/view/animation/Interpolator;',
		time_animator_method('public static loadInterpolator(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;I)Landroid/view/animation/Interpolator;', 5, '
const/4 v0, 0
:try_start
invoke-virtual {p0, p2}, Landroid/content/res/Resources;->getAnimation(I)Landroid/content/res/XmlResourceParser;
move-result-object v0
invoke-static {p0, p1, v0}, Landroid/view/animation/VinixInterpolatorXml;->parse(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/content/res/XmlResourceParser;)Landroid/view/animation/Interpolator;
move-result-object v1
:try_end
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
return-object v1
.catch Lorg/xmlpull/v1/XmlPullParserException; {:try_start .. :try_end} :xml_error
.catch Ljava/io/IOException; {:try_start .. :try_end} :xml_error
.catch Landroid/view/InflateException; {:try_start .. :try_end} :xml_error
.catchall {:try_start .. :try_end} :cleanup
:xml_error
move-exception v1
if-eqz v0, :wrap
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
:wrap
new-instance v2, Ljava/lang/StringBuilder;
invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
const-string v3, "Cannot load interpolator resource #0x"
invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {p2}, Ljava/lang/Integer;->toHexString(I)Ljava/lang/String;
move-result-object v3
invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v2
new-instance v3, Landroid/content/res/Resources$NotFoundException;
invoke-direct {v3, v2}, Landroid/content/res/Resources$NotFoundException;-><init>(Ljava/lang/String;)V
invoke-virtual {v3, v1}, Ljava/lang/Throwable;->initCause(Ljava/lang/Throwable;)Ljava/lang/Throwable;
throw v3
:cleanup
move-exception v1
if-eqz v0, :rethrow
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
:rethrow
throw v1'))!
	os.write_file(utils, text)!
	cls := 'Landroid/view/animation/VinixInterpolatorXml;'
	mut helper := '.class public final ${cls}\n.super Ljava/lang/Object;\n'
	helper += time_animator_method('public static attributes(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/util/AttributeSet;[I)Landroid/content/res/TypedArray;', 2, '
if-eqz p1, :resources
const/4 v0, 0
invoke-virtual {p1, p2, p3, v0, v0}, Landroid/content/res/Resources$Theme;->obtainStyledAttributes(Landroid/util/AttributeSet;[III)Landroid/content/res/TypedArray;
move-result-object v0
return-object v0
:resources
invoke-virtual {p0, p2, p3}, Landroid/content/res/Resources;->obtainAttributes(Landroid/util/AttributeSet;[I)Landroid/content/res/TypedArray;
move-result-object v0
return-object v0')
	mut parse := '
:next
invoke-interface {p2}, Lorg/xmlpull/v1/XmlPullParser;->next()I
move-result v0
const/4 v1, 1
if-eq v0, v1, :empty
const/4 v1, 2
if-ne v0, v1, :next
invoke-interface {p2}, Lorg/xmlpull/v1/XmlPullParser;->getName()Ljava/lang/String;
move-result-object v0
invoke-static {p2}, Landroid/util/Xml;->asAttributeSet(Lorg/xmlpull/v1/XmlPullParser;)Landroid/util/AttributeSet;
move-result-object v1
'
	for name in ['Linear', 'Accelerate', 'Decelerate', 'AccelerateDecelerate', 'Cycle', 'Anticipate',
		'Overshoot', 'AnticipateOvershoot', 'Bounce', 'Path'] {
		tag := name[..1].to_lower() + name[1..] + 'Interpolator'
		c := 'Landroid/view/animation/${name}Interpolator;'
		parse += 'const-string v2, "${tag}"\ninvoke-virtual {v2, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v2\nif-eqz v2, :not_${name}\nnew-instance v3, ${c}\n'
		if name in ['Linear', 'AccelerateDecelerate', 'Bounce'] {
			parse += 'invoke-direct {v3}, ${c}-><init>()V\n'
		} else {
			parse += 'invoke-direct {v3, p0, p1, v1}, ${c}-><init>(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/util/AttributeSet;)V\n'
		}
		parse += 'goto :parsed\n:not_${name}\n'
	}
	parse += '
new-instance v1, Ljava/lang/StringBuilder;
invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V
const-string v2, "Unknown interpolator name: "
invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v1, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v0
goto :invalid
:parsed
invoke-interface {p2}, Lorg/xmlpull/v1/XmlPullParser;->next()I
move-result v0
const/4 v1, 1
if-eq v0, v1, :done
const/4 v1, 2
if-ne v0, v1, :parsed
const-string v0, "Interpolator cannot contain child elements"
goto :invalid
:done
return-object v3
:empty
const-string v0, "Interpolator XML has no start tag"
:invalid
new-instance v1, Landroid/view/InflateException;
invoke-direct {v1, v0}, Landroid/view/InflateException;-><init>(Ljava/lang/String;)V
throw v1'
	helper += time_animator_method('public static parse(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/content/res/XmlResourceParser;)Landroid/view/animation/Interpolator;', 4, parse)
	os.write_file(smali + '/android/view/animation/VinixInterpolatorXml.smali', helper)!
	framework_scalar_interpolators(smali)!
	framework_bezier_interpolator(smali)!
}

// Every XML class has the normal constructor family as well. Typed arrays are
// recycled on failure as well as success; attribute references use Resources.
fn framework_scalar_interpolators(smali string) ! {
	for name, default_value in {
		'Accelerate':          '0x3f800000'
		'Decelerate':          '0x3f800000'
		'Cycle':               '0x3f800000'
		'Anticipate':          '0x40000000'
		'Overshoot':           '0x40000000'
		'AnticipateOvershoot': '0x40000000'
	} {
		c := 'Landroid/view/animation/${name}Interpolator;'
		mut text := '.class public ${c}\n.super Landroid/view/animation/BaseInterpolator;\n.field private value:F\n'
		text += time_animator_method('public constructor <init>()V', 1,
			'const v0, ${default_value}\ninvoke-direct {p0, v0}, ${c}-><init>(F)V\nreturn-void')
		mut init := 'invoke-direct {p0}, Landroid/view/animation/BaseInterpolator;-><init>()V\n'
		if name == 'AnticipateOvershoot' {
			init += 'const v0, 0x3fc00000\nmul-float p1, p1, v0\n'
			text += time_animator_method('public constructor <init>(FF)V', 0,
				'invoke-direct {p0}, Landroid/view/animation/BaseInterpolator;-><init>()V\nmul-float p1, p1, p2\niput p1, p0, ${c}->value:F\nreturn-void')
		}
		text += time_animator_method('public constructor <init>(F)V', 1,
			init + 'iput p1, p0, ${c}->value:F\nreturn-void')
		text += interpolator_context_constructor(c)
		mut attrs := '
invoke-direct {p0}, Landroid/view/animation/BaseInterpolator;-><init>()V
sget-object v0, Lcom/android/internal/R$styleable;->${name}Interpolator:[I
invoke-static {p1, p2, p3, v0}, Landroid/view/animation/VinixInterpolatorXml;->attributes(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/util/AttributeSet;[I)Landroid/content/res/TypedArray;
move-result-object v0
:try_start
const/4 v1, 0
const v2, ${default_value}
invoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getFloat(IF)F
move-result v1
'
		if name == 'AnticipateOvershoot' {
			attrs += 'const/4 v2, 1\nconst v3, 0x3fc00000\ninvoke-virtual {v0, v2, v3}, Landroid/content/res/TypedArray;->getFloat(IF)F\nmove-result v2\nmul-float/2addr v1, v2\n'
		}
		attrs += 'iput v1, p0, ${c}->value:F\n:try_end\ninvoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V\nreturn-void\n.catchall {:try_start .. :try_end} :cleanup\n:cleanup\nmove-exception v1\ninvoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V\nthrow v1'
		text += time_animator_method('public constructor <init>(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/util/AttributeSet;)V', 4, attrs)
		mut body := 'iget v0, p0, ${c}->value:F\n'
		match name {
			'Accelerate', 'Decelerate' {
				if name == 'Decelerate' { body += 'const v4, 0x3f800000\nsub-float p1, v4, p1\n' }
				body += 'const v1, 0x40000000\nmul-float/2addr v0, v1\nfloat-to-double v2, v0\nfloat-to-double v0, p1\ninvoke-static {v0, v1, v2, v3}, Ljava/lang/Math;->pow(DD)D\nmove-result-wide v0\ndouble-to-float v0, v0\n'
				if name == 'Decelerate' { body += 'sub-float v0, v4, v0\n' }
			}
			'Cycle' {
				body += 'mul-float v0, v0, p1\nfloat-to-double v0, v0\nconst-wide v2, 0x401921fb54442d18L\nmul-double/2addr v0, v2\ninvoke-static {v0, v1}, Ljava/lang/Math;->sin(D)D\nmove-result-wide v0\ndouble-to-float v0, v0\n'
			}
			'Anticipate', 'Overshoot' {
				if name == 'Overshoot' { body += 'const v1, 0x3f800000\nsub-float/2addr p1, v1\n' }
				body += 'const v1, 0x3f800000\nadd-float v2, v0, v1\nmul-float/2addr v2, p1\n'
				body += if name == 'Anticipate' {
					'sub-float/2addr v2, v0\n'
				} else {
					'add-float/2addr v2, v0\n'
				}
				body += 'mul-float v0, p1, p1\nmul-float/2addr v0, v2\n'
				if name == 'Overshoot' { body += 'add-float/2addr v0, v1\n' }
			}
			'AnticipateOvershoot' {
				body += '
const v1, 0x3f000000
const v2, 0x40000000
cmpg-float v3, p1, v1
mul-float/2addr p1, v2
if-gez v3, :over
const v3, 0x3f800000
add-float/2addr v3, v0
mul-float/2addr v3, p1
sub-float/2addr v3, v0
mul-float v0, p1, p1
mul-float/2addr v0, v3
mul-float/2addr v0, v1
goto :result
:over
sub-float/2addr p1, v2
const v3, 0x3f800000
add-float/2addr v3, v0
mul-float/2addr v3, p1
add-float/2addr v3, v0
mul-float v0, p1, p1
mul-float/2addr v0, v3
add-float/2addr v0, v2
mul-float/2addr v0, v1
:result
'
			}
			else {}
		}
		text += time_animator_method('public getInterpolation(F)F', 5, body + 'return v0')
		os.write_file(smali + '/android/view/animation/${name}Interpolator.smali', text)!
	}
	// The remaining stateless classes need only their two normal constructors.
	for name in ['Linear', 'AccelerateDecelerate', 'Bounce'] {
		c := 'Landroid/view/animation/${name}Interpolator;'
		mut text := '.class public ${c}\n.super Landroid/view/animation/BaseInterpolator;\n'
		text += time_animator_method('public constructor <init>()V', 0,
			'invoke-direct {p0}, Landroid/view/animation/BaseInterpolator;-><init>()V\nreturn-void')
		text += time_animator_method('public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V', 0,
			'invoke-direct {p0}, ${c}-><init>()V\nreturn-void')
		body := match name {
			'Linear' { 'return p1' }
			'AccelerateDecelerate' {
				'
float-to-double v0, p1
const-wide/high16 v2, 0x3ff0000000000000L
add-double/2addr v0, v2
const-wide v2, 0x400921fb54442d18L
mul-double/2addr v0, v2
invoke-static {v0, v1}, Ljava/lang/Math;->cos(D)D
move-result-wide v0
const-wide/high16 v2, 0x4000000000000000L
div-double/2addr v0, v2
const-wide/high16 v2, 0x3fe0000000000000L
add-double/2addr v0, v2
double-to-float v0, v0
return v0'
			}
			else {
				'
const v0, 0x3f8fb15b
mul-float/2addr p1, v0
const/4 v1, 0
const v0, 0x3eb4fdf4
cmpg-float v2, p1, v0
if-ltz v2, :bounce
const v0, 0x3f3da512
cmpg-float v2, p1, v0
if-gez v2, :third
const v0, 0x3f0c14a5
sub-float/2addr p1, v0
const v1, 0x3f333333
goto :bounce
:third
const v0, 0x3f76e2eb
cmpg-float v2, p1, v0
if-gez v2, :fourth
const v0, 0x3f5a43fe
sub-float/2addr p1, v0
const v1, 0x3f666666
goto :bounce
:fourth
const v0, 0x3f859168
sub-float/2addr p1, v0
const v1, 0x3f733333
:bounce
mul-float v0, p1, p1
const v2, 0x41000000
mul-float/2addr v0, v2
add-float/2addr v0, v1
return v0'
			}
		}
		text += time_animator_method('public getInterpolation(F)F', 4, body)
		os.write_file(smali + '/android/view/animation/${name}Interpolator.smali', text)!
	}
}

fn interpolator_context_constructor(c string) string {
	return time_animator_method('public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V', 2,
		'invoke-virtual {p1}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;\nmove-result-object v0\ninvoke-virtual {p1}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;\nmove-result-object v1\ninvoke-direct {p0, v0, v1, p2}, ${c}-><init>(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/util/AttributeSet;)V\nreturn-void')
}

fn framework_bezier_interpolator(smali string) ! {
	// ATL keeps its SVG parser in drawable rather than android.util. Its public
	// static parser is shared by framework interpolators as well as drawables.
	parser := smali + '/android/graphics/drawable/PathParser.smali'
	parser_source := os.read_file(parser)!
	if !parser_source.starts_with('.class Landroid/graphics/drawable/PathParser;') {
		return error('unexpected framework PathParser visibility')
	}
	os.write_file(parser, parser_source.replace('.class Landroid/graphics/drawable/PathParser;',
		'.class public Landroid/graphics/drawable/PathParser;'))!
	// Reuse the existing rooted JNI snapshot: native pointers never escape into
	// the interpolator, and later Path mutation cannot change its samples.
	values := smali + '/android/animation/VinixPathValues.smali'
	mut source := os.read_file(values)!
	source = framework_replace_method(source, 'snapshotPath(Landroid/graphics/Path;)[F',
		time_animator_method('public static snapshotPath(Landroid/graphics/Path;)[F', 2, '
invoke-virtual {p0}, Landroid/graphics/Path;->getGskPath()J
move-result-wide v0
invoke-static {p0, v0, v1}, Landroid/animation/VinixPathValues;->nativePath(Landroid/graphics/Path;J)[F
move-result-object v0
return-object v0'))!
	os.write_file(values, source)!
	c := 'Landroid/view/animation/PathInterpolator;'
	mut text := '.class public ${c}\n.super Landroid/view/animation/BaseInterpolator;\n.field private x1:F\n.field private y1:F\n.field private x2:F\n.field private y2:F\n.field private samples:[F\n'
	text += time_animator_method('public constructor <init>(FFFF)V', 0, '
invoke-direct {p0}, Landroid/view/animation/BaseInterpolator;-><init>()V
invoke-direct {p0, p1, p2, p3, p4}, ${c}->initCubic(FFFF)V
return-void')
	text += time_animator_method('public constructor <init>(FF)V', 4, '
const v0, 0x3f2aaaab
mul-float v1, p1, v0
mul-float v2, p2, v0
const v3, 0x3eaaaaab
add-float v0, v1, v3
add-float v3, v2, v3
invoke-direct {p0, v1, v2, v0, v3}, ${c}-><init>(FFFF)V
return-void')
	text += time_animator_method('public constructor <init>(Landroid/graphics/Path;)V', 0, '
invoke-direct {p0}, Landroid/view/animation/BaseInterpolator;-><init>()V
invoke-direct {p0, p1}, ${c}->initPath(Landroid/graphics/Path;)V
return-void')
	text += interpolator_context_constructor(c)
	text += time_animator_method('public constructor <init>(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/util/AttributeSet;)V', 2, '
invoke-direct {p0}, Landroid/view/animation/BaseInterpolator;-><init>()V
sget-object v0, Lcom/android/internal/R$styleable;->PathInterpolator:[I
invoke-static {p1, p2, p3, v0}, Landroid/view/animation/VinixInterpolatorXml;->attributes(Landroid/content/res/Resources;Landroid/content/res/Resources$Theme;Landroid/util/AttributeSet;[I)Landroid/content/res/TypedArray;
move-result-object v0
:try_start
invoke-direct {p0, v0}, ${c}->parseAttributes(Landroid/content/res/TypedArray;)V
:try_end
invoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V
return-void
.catchall {:try_start .. :try_end} :cleanup
:cleanup
move-exception v1
invoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V
throw v1')
	text += time_animator_method('private parseAttributes(Landroid/content/res/TypedArray;)V', 7, '
const/4 v0, 4
invoke-virtual {p1, v0}, Landroid/content/res/TypedArray;->hasValue(I)Z
move-result v1
if-eqz v1, :controls
invoke-virtual {p1, v0}, Landroid/content/res/TypedArray;->getString(I)Ljava/lang/String;
move-result-object v0
invoke-static {v0}, Landroid/graphics/drawable/PathParser;->createPathFromPathData(Ljava/lang/String;)Landroid/graphics/Path;
move-result-object v0
if-eqz v0, :invalid
invoke-direct {p0, v0}, ${c}->initPath(Landroid/graphics/Path;)V
return-void
:controls
const/4 v0, 0
invoke-virtual {p1, v0}, Landroid/content/res/TypedArray;->hasValue(I)Z
move-result v1
if-eqz v1, :invalid
const/4 v1, 1
invoke-virtual {p1, v1}, Landroid/content/res/TypedArray;->hasValue(I)Z
move-result v2
if-eqz v2, :invalid
const/4 v6, 0
invoke-virtual {p1, v0, v6}, Landroid/content/res/TypedArray;->getFloat(IF)F
move-result v2
invoke-virtual {p1, v1, v6}, Landroid/content/res/TypedArray;->getFloat(IF)F
move-result v3
const/4 v0, 2
const/4 v1, 3
invoke-virtual {p1, v0}, Landroid/content/res/TypedArray;->hasValue(I)Z
move-result v4
invoke-virtual {p1, v1}, Landroid/content/res/TypedArray;->hasValue(I)Z
move-result v5
if-ne v4, v5, :invalid
if-nez v4, :cubic
const v0, 0x3f2aaaab
mul-float/2addr v2, v0
mul-float/2addr v3, v0
const v0, 0x3eaaaaab
add-float v4, v2, v0
add-float v5, v3, v0
goto :init
:cubic
invoke-virtual {p1, v0, v6}, Landroid/content/res/TypedArray;->getFloat(IF)F
move-result v4
invoke-virtual {p1, v1, v6}, Landroid/content/res/TypedArray;->getFloat(IF)F
move-result v5
:init
invoke-direct {p0, v2, v3, v4, v5}, ${c}->initCubic(FFFF)V
return-void
:invalid
new-instance v0, Landroid/view/InflateException;
const-string v1, "pathInterpolator requires pathData or controlX1/controlY1 and paired controlX2/controlY2"
invoke-direct {v0, v1}, Landroid/view/InflateException;-><init>(Ljava/lang/String;)V
throw v0')
	text += time_animator_method('private static finite(F)V', 2, '
invoke-static {p0}, Ljava/lang/Float;->isNaN(F)Z
move-result v0
if-nez v0, :invalid
invoke-static {p0}, Ljava/lang/Float;->isInfinite(F)Z
move-result v0
if-nez v0, :invalid
return-void
:invalid
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Interpolator coordinates must be finite"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0')
	text += time_animator_method('private initCubic(FFFF)V', 0, '
invoke-static {p1}, ${c}->finite(F)V
invoke-static {p2}, ${c}->finite(F)V
invoke-static {p3}, ${c}->finite(F)V
invoke-static {p4}, ${c}->finite(F)V
invoke-static {p1, p3}, ${c}->validateX(FF)V
iput p1, p0, ${c}->x1:F
iput p2, p0, ${c}->y1:F
iput p3, p0, ${c}->x2:F
iput p4, p0, ${c}->y2:F
return-void')
	// x'(t)/3 = A*t*t+B*t+C. Test endpoints and the interior
	// minimum, using doubles so finite float controls cannot overflow the test.
	text += time_animator_method('private static validateX(FF)V', 12, '
float-to-double v0, p0
float-to-double v2, p1
const-wide/16 v4, 0
cmpg-double v6, v0, v4
if-ltz v6, :invalid
const-wide/high16 v4, 0x3ff0000000000000L
cmpl-double v6, v2, v4
if-gtz v6, :invalid
sub-double v6, v0, v2
const-wide/high16 v8, 0x4008000000000000L
mul-double/2addr v6, v8
add-double/2addr v6, v4
const-wide/high16 v8, 0x4000000000000000L
mul-double v10, v0, v8
sub-double/2addr v2, v10
mul-double/2addr v2, v8
const-wide/16 v10, 0
cmpg-double v10, v6, v10
if-lez v10, :valid
mul-double/2addr v8, v6
neg-double v10, v2
div-double/2addr v10, v8
const-wide/16 v8, 0
cmpg-double v8, v10, v8
if-lez v8, :valid
cmpl-double v8, v10, v4
if-gez v8, :valid
mul-double/2addr v6, v10
add-double/2addr v6, v2
mul-double/2addr v6, v10
add-double/2addr v6, v0
const-wide/16 v8, 0
cmpg-double v8, v6, v8
if-ltz v8, :invalid
:valid
return-void
:invalid
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "The Path cannot loop back on itself"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0')
	text += time_animator_method('private static bezier(FFF)F', 10, '
float-to-double v0, p1
float-to-double v2, p2
float-to-double v4, p0
const-wide/high16 v6, 0x4008000000000000L
mul-double/2addr v0, v6
mul-double/2addr v2, v6
const-wide/high16 v6, 0x3ff0000000000000L
add-double/2addr v6, v0
sub-double/2addr v6, v2
mul-double/2addr v6, v4
const-wide/high16 v8, 0x4000000000000000L
mul-double/2addr v8, v0
sub-double/2addr v2, v8
add-double/2addr v6, v2
mul-double/2addr v6, v4
add-double/2addr v6, v0
mul-double/2addr v6, v4
double-to-float v0, v6
return v0')
	text += time_animator_method('private initPath(Landroid/graphics/Path;)V', 8, '
invoke-static {p1}, Landroid/animation/VinixPathValues;->snapshotPath(Landroid/graphics/Path;)[F
move-result-object v0
array-length v1, v0
const/4 v2, 6
if-lt v1, v2, :invalid
const/4 v2, 1
aget v3, v0, v2
const/4 v4, 0
cmpl-float v3, v3, v4
if-nez v3, :invalid
const/4 v2, 2
aget v3, v0, v2
cmpl-float v3, v3, v4
if-nez v3, :invalid
add-int/lit8 v2, v1, -2
aget v3, v0, v2
const v5, 0x3f800000
cmpl-float v3, v3, v5
if-nez v3, :invalid
add-int/lit8 v2, v2, 1
aget v3, v0, v2
cmpl-float v3, v3, v5
if-nez v3, :invalid
const/4 v2, 0
const/4 v5, 0
:point
aget v3, v0, v2
invoke-static {v3}, ${c}->finite(F)V
add-int/lit8 v6, v2, 1
aget v6, v0, v6
invoke-static {v6}, ${c}->finite(F)V
add-int/lit8 v7, v2, 2
aget v7, v0, v7
invoke-static {v7}, ${c}->finite(F)V
cmpg-float v7, v6, v4
if-ltz v7, :invalid
cmpl-float v7, v3, v5
if-nez v7, :continuous
cmpl-float v7, v6, v4
if-nez v7, :invalid
:continuous
move v4, v6
move v5, v3
add-int/lit8 v2, v2, 3
if-lt v2, v1, :point
iput-object v0, p0, ${c}->samples:[F
return-void
:invalid
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Path must run continuously in X from (0,0) to (1,1) without reversing"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0')
	text += time_animator_method('public getInterpolation(F)F', 8, '
const/4 v0, 0
cmpg-float v1, p1, v0
if-lez v1, :zero
const v1, 0x3f800000
cmpl-float v2, p1, v1
if-gez v2, :one
iget-object v2, p0, ${c}->samples:[F
if-nez v2, :samples
const/4 v2, 0
const/16 v3, 32
:solve
add-float v4, v0, v1
const v5, 0x3f000000
mul-float/2addr v4, v5
iget v5, p0, ${c}->x1:F
iget v6, p0, ${c}->x2:F
invoke-static {v4, v5, v6}, ${c}->bezier(FFF)F
move-result v5
cmpg-float v5, v5, p1
if-ltz v5, :lower
move v1, v4
goto :step
:lower
move v0, v4
:step
add-int/lit8 v2, v2, 1
if-lt v2, v3, :solve
iget v0, p0, ${c}->y1:F
iget v1, p0, ${c}->y2:F
invoke-static {v4, v0, v1}, ${c}->bezier(FFF)F
move-result v0
return v0
:samples
const/4 v0, 0
array-length v1, v2
div-int/lit8 v1, v1, 3
add-int/lit8 v1, v1, -1
:search
sub-int v3, v1, v0
const/4 v4, 1
if-le v3, v4, :between
add-int v3, v0, v1
div-int/lit8 v3, v3, 2
mul-int/lit8 v4, v3, 3
add-int/lit8 v4, v4, 1
aget v4, v2, v4
cmpg-float v4, p1, v4
if-ltz v4, :left
move v0, v3
goto :search
:left
move v1, v3
goto :search
:between
mul-int/lit8 v0, v0, 3
mul-int/lit8 v1, v1, 3
add-int/lit8 v0, v0, 1
add-int/lit8 v1, v1, 1
aget v3, v2, v0
aget v4, v2, v1
sub-float/2addr v4, v3
add-int/lit8 v0, v0, 1
add-int/lit8 v1, v1, 1
aget v0, v2, v0
const/4 v5, 0
cmpl-float v5, v4, v5
if-eqz v5, :return
sub-float v3, p1, v3
div-float/2addr v3, v4
aget v1, v2, v1
sub-float/2addr v1, v0
mul-float/2addr v1, v3
add-float/2addr v0, v1
:return
return v0
:zero
const/4 v0, 0
return v0
:one
return v1')
	os.write_file(smali + '/android/view/animation/PathInterpolator.smali', text)!
}
