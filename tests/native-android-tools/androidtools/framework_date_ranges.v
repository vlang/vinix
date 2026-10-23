// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// ART already supplies ICU's range formatting, including locale, time zone and
// midnight interval handling. Match DateUtils' public wrappers around that API.
fn framework_date_ranges(smali string) ! {
	path := smali + '/android/text/format/DateUtils.smali'
	mut text := os.read_file(path)!
	date := 'Landroid/text/format/DateUtils;'
	fmt := 'Ljava/util/Formatter;'
	context := 'Landroid/content/Context;'
	full := 'formatDateRange(' + context + fmt + 'JJI' + 'Ljava/lang/String;)' + fmt
	text += '\n.method public static ' + full + '\n.locals 2\n' +
		'and-int/lit16 v0, p6, 0xc1\nconst/4 v1, 1\nif-ne v0, v1, :format\n' +
		'invoke-static {p0}, Landroid/text/format/DateFormat;->is24HourFormat(' + context + ')Z\nmove-result v0\n' +
		'if-eqz v0, :twelve\nor-int/lit16 p6, p6, 0x80\ngoto :format\n:twelve\nor-int/lit8 p6, p6, 0x40\n' +
		':format\ninvoke-static/range {p2 .. p7}, Llibcore/icu/DateIntervalFormat;->formatDateRange(JJILjava/lang/String;)Ljava/lang/String;\nmove-result-object v0\n' +
		':try_start\ninvoke-virtual {p1}, ' + fmt + '->out()Ljava/lang/Appendable;\nmove-result-object v1\n' +
		'invoke-interface {v1, v0}, Ljava/lang/Appendable;->append(Ljava/lang/CharSequence;)Ljava/lang/Appendable;\n:try_end\nreturn-object p1\n' +
		'.catch Ljava/io/IOException; {:try_start .. :try_end} :io_error\n:io_error\nmove-exception v0\nnew-instance v1, Ljava/lang/AssertionError;\n' +
		'invoke-direct {v1, v0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v1\n.end method\n'
	short := 'formatDateRange(' + context + fmt + 'JJI)' + fmt
	text += '\n.method public static ' + short + '\n.locals 8\n' +
		'move-object v0, p0\nmove-object v1, p1\nmove-wide v2, p2\nmove-wide v4, p4\nmove v6, p6\nconst/4 v7, 0\n' +
		'invoke-static/range {v0 .. v7}, ' + date + '->' + full + '\nmove-result-object v0\nreturn-object v0\n.end method\n'
	string_range := 'formatDateRange(' + context + 'JJI)Ljava/lang/String;'
	text = framework_replace_method(text, string_range,
		'.method public static ' + string_range + '\n.locals 8\n' +
			'move-object v0, p0\nnew-instance v1, ' + fmt + '\ninvoke-direct {v1}, ' + fmt + '-><init>()V\n' +
			'move-wide v2, p1\nmove-wide v4, p3\nmove v6, p5\nconst/4 v7, 0\n' +
			'invoke-static/range {v0 .. v7}, ' + date + '->' + full + '\nmove-result-object v0\n' +
			'invoke-virtual {v0}, ' + fmt + '->toString()Ljava/lang/String;\nmove-result-object v0\nreturn-object v0\n.end method')!
	point := 'formatDateTime(' + context + 'JI)Ljava/lang/String;'
	text = framework_replace_method(text, point,
		'.method public static ' + point + '\n.locals 6\n' +
			'move-object v0, p0\nmove-wide v1, p1\nmove-wide v3, p1\nmove v5, p3\n' +
			'invoke-static/range {v0 .. v5}, ' + date + '->' + string_range + '\nmove-result-object v0\nreturn-object v0\n.end method')!
	os.write_file(path, text)!
}
