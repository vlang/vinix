// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_blur_styles(smali string) ! {
	path := smali + '/android/graphics/BlurMaskFilter$Blur.smali'
	c := 'Landroid/graphics/BlurMaskFilter$Blur;'
	mut text := os.read_file(path)!
	mut fields := '.field final native_int:I\n'
	for name in ['SOLID', 'OUTER', 'INNER'] {
		fields += '.field public static final enum ${name}:${c}\n'
	}
	text += '\n' + fields
	mut body := '.method static constructor <clinit>()V\n.locals 4\nconst/4 v0, 4\nnew-array v0, v0, [${c}\n'
	for i, name in ['NORMAL', 'SOLID', 'OUTER', 'INNER'] {
		body += 'new-instance v1, ${c}\nconst-string v2, "${name}"\nconst/4 v3, ${i}\n' +
			'invoke-direct {v1, v2, v3}, ${c}-><init>(Ljava/lang/String;I)V\n' +
			'sput-object v1, ${c}->${name}:${c}\naput-object v1, v0, v3\n'
	}
	body += 'sput-object v0, ${c}->$VALUES:[${c}\nreturn-void\n.end method'
	text = framework_replace_method(text, '<clinit>()V', body)!
	text = framework_replace_method(text, '<init>(Ljava/lang/String;I)V',
		'.method private constructor <init>(Ljava/lang/String;I)V\n.locals 0\n' +
			'invoke-direct {p0, p1, p2}, Ljava/lang/Enum;-><init>(Ljava/lang/String;I)V\n' +
			'iput p2, p0, ${c}->native_int:I\nreturn-void\n.end method')!
	os.write_file(path, text)!
}
