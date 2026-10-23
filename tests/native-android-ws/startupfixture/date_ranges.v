// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

const date_range_probe = 'Lorg/vinix/bootstrap/DateRangesProbe;'
const date_range_api = 'Landroid/text/format/DateUtils;'
const date_range_formatter = 'Ljava/util/Formatter;'
const date_range_full = 'formatDateRange(Landroid/content/Context;Ljava/util/Formatter;JJILjava/lang/String;)Ljava/util/Formatter;'

fn date_range_case(start i64, end i64, flags int, zone string, expected string) string {
	tz := if zone == '' { 'const/4 v5, 0' } else { 'const-string v5, "${zone}"' }
	return 'const-wide v0, ${start}L\nconst-wide v2, ${end}L\nconst v4, ${flags}\n${tz}\nconst-string v6, "${expected}"\ninvoke-static/range {v0 .. v6}, ${date_range_probe}->sample(JJILjava/lang/String;Ljava/lang/String;)V\n'
}

fn date_range_failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn install_date_ranges_probe(dir string) ! {
	c := date_range_probe
	f := date_range_formatter
	d := date_range_api
	full := date_range_full
	start := i64(1704200700000) // 2024-01-02T13:05:00Z, independent fixed calendar values.
	end := i64(1704208200000) // 2024-01-02T15:10:00Z.
	mut source := '.class public ${c}\n.super Ljava/lang/Object;\n.field private static context:Landroid/content/Context;\n'
	source += method('public static check(Landroid/content/Context;)V', '
sput-object p0, ${c}->context:Landroid/content/Context;
invoke-static {}, Ljava/util/Locale;->getDefault()Ljava/util/Locale;
move-result-object v8
invoke-static {}, Ljava/util/TimeZone;->getDefault()Ljava/util/TimeZone;
move-result-object v9
sget-object v0, Ljava/util/Locale$Category;->DISPLAY:Ljava/util/Locale$Category;
invoke-static {v0}, Ljava/util/Locale;->getDefault(Ljava/util/Locale$Category;)Ljava/util/Locale;
move-result-object v6
sget-object v0, Ljava/util/Locale$Category;->FORMAT:Ljava/util/Locale$Category;
invoke-static {v0}, Ljava/util/Locale;->getDefault(Ljava/util/Locale$Category;)Ljava/util/Locale;
move-result-object v5
:start
sget-object v0, Ljava/util/Locale;->US:Ljava/util/Locale;
invoke-static {v0}, Ljava/util/Locale;->setDefault(Ljava/util/Locale;)V
const-string v0, "America/Los_Angeles"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
invoke-static {v0}, Ljava/util/TimeZone;->setDefault(Ljava/util/TimeZone;)V
invoke-static {}, ${c}->cases()V
invoke-static {}, ${c}->wrappers()V
invoke-static {}, ${c}->errors()V
:end
invoke-static {v8}, Ljava/util/Locale;->setDefault(Ljava/util/Locale;)V
sget-object v0, Ljava/util/Locale$Category;->DISPLAY:Ljava/util/Locale$Category;
invoke-static {v0, v6}, Ljava/util/Locale;->setDefault(Ljava/util/Locale$Category;Ljava/util/Locale;)V
sget-object v0, Ljava/util/Locale$Category;->FORMAT:Ljava/util/Locale$Category;
invoke-static {v0, v5}, Ljava/util/Locale;->setDefault(Ljava/util/Locale$Category;Ljava/util/Locale;)V
invoke-static {v9}, Ljava/util/TimeZone;->setDefault(Ljava/util/TimeZone;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-DATE-RANGES-PASS formatter-identity percent-prefix repeated-append default-locale timezone-null-UTC-explicit 12h-24h-preference range-date-endpoints string-point-wrappers closed-formatter IO-cause"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.catchall {:start .. :end} :restore
:restore
move-exception v7
invoke-static {v8}, Ljava/util/Locale;->setDefault(Ljava/util/Locale;)V
sget-object v0, Ljava/util/Locale$Category;->DISPLAY:Ljava/util/Locale$Category;
invoke-static {v0, v6}, Ljava/util/Locale;->setDefault(Ljava/util/Locale$Category;Ljava/util/Locale;)V
sget-object v0, Ljava/util/Locale$Category;->FORMAT:Ljava/util/Locale$Category;
invoke-static {v0, v5}, Ljava/util/Locale;->setDefault(Ljava/util/Locale$Category;Ljava/util/Locale;)V
invoke-static {v9}, Ljava/util/TimeZone;->setDefault(Ljava/util/TimeZone;)V
throw v7')
	mut cases := date_range_case(start, start, 0x81, 'UTC', '13:05')
	cases += date_range_case(start, start, 0x41, 'UTC', '1:05PM')
	cases += date_range_case(start, start, 0xc1, 'UTC', '13:05')
	cases += date_range_case(start, start, 1, 'UTC', '13:05')
	cases += date_range_case(start, start, 0x81, '', '05:05')
	cases += date_range_case(start, start, 0x81, 'America/Los_Angeles', '05:05')
	cases += date_range_case(start, start, 0x81, 'Asia/Kolkata', '18:35')
	cases += date_range_case(start, start, 0x2081, '', '13:05')
	// The deployed libcore gives FORMAT_UTC precedence over a supplied zone.
	cases += date_range_case(start, start, 0x2081, 'America/Los_Angeles', '13:05')
	cases += date_range_case(start, end, 0x81, 'UTC', '13:05-15:10')
	cases += date_range_case(start, start, 0x20014, 'UTC', '1/2/2024')
	cases += 'const-wide v0, ${start}L\nconst-wide v2, ${end + 86400000}L\nconst v4, 0x20095\nconst-string v5, "UTC"\ninvoke-static/range {v0 .. v5}, ${c}->render(JJILjava/lang/String;)Ljava/lang/String;\nmove-result-object v7\n'
	for token in ['1/2/2024', '1/3/2024', '13:05', '15:10'] {
		cases += 'move-object v0, v7\nconst-string v1, "${token}"\ninvoke-static {v0, v1}, ${c}->contains(Ljava/lang/String;Ljava/lang/String;)V\n'
	}
	source += method('private static cases()V', cases + 'return-void')
	source += method('private static render(JJILjava/lang/String;)Ljava/lang/String;', '
sget-object v0, ${c}->context:Landroid/content/Context;
new-instance v1, ${f}
# Formatter.locale is deliberately different: DateUtils follows the default locale.
sget-object v8, Ljava/util/Locale;->FRANCE:Ljava/util/Locale;
invoke-direct {v1, v8}, ${f}-><init>(Ljava/util/Locale;)V
move-wide v2, p0
move-wide v4, p2
move v6, p4
move-object v7, p5
# First new API reached by the old framework, preserving a precise baseline.
invoke-static/range {v0 .. v7}, ${d}->${full}
move-result-object v0
if-ne v0, v1, :bad
invoke-virtual {v1}, ${f}->toString()Ljava/lang/String;
move-result-object v0
return-object v0
' + date_range_failure('DateUtils returned a different Formatter'))
	source += method('private static sample(JJILjava/lang/String;Ljava/lang/String;)V', '
invoke-static/range {p0 .. p5}, ${c}->render(JJILjava/lang/String;)Ljava/lang/String;
move-result-object v0
move-object/from16 v1, p6
invoke-static {v0, v1}, ${c}->expect(Ljava/lang/String;Ljava/lang/String;)V
return-void')
	mut normalize := 'move-object v0, p0\nconst-string v2, ""\n'
	for space in [' ', '\u00a0', '\u202f', '\u2009'] {
		normalize += 'const-string v1, "${space}"\ninvoke-virtual {v0, v1, v2}, Ljava/lang/String;->replace(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;\nmove-result-object v0\n'
	}
	normalize += 'const-string v1, "–"\nconst-string v2, "-"\ninvoke-virtual {v0, v1, v2}, Ljava/lang/String;->replace(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;\nmove-result-object v0\nreturn-object v0'
	source += method('private static normalize(Ljava/lang/String;)Ljava/lang/String;', normalize)
	source += method('private static expect(Ljava/lang/String;Ljava/lang/String;)V', '
invoke-static {p0}, ${c}->normalize(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
:bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v0, p0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0, p1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "DateUtils calendar value"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	source += method('private static contains(Ljava/lang/String;Ljava/lang/String;)V', '
invoke-static {p0}, ${c}->normalize(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
move-result v0
if-eqz v0, :bad
return-void
' + date_range_failure('DateUtils cross-day endpoint missing'))
	source += method('private static wrappers()V', '
new-instance v8, Ljava/lang/StringBuilder;
const-string v0, "load100%:"
invoke-direct {v8, v0}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
new-instance v9, ${f}
invoke-direct {v9, v8}, ${f}-><init>(Ljava/lang/Appendable;)V
sget-object v0, ${c}->context:Landroid/content/Context;
move-object v1, v9
const-wide v2, ${start}L
const-wide v4, ${end}L
const/16 v6, 0x81
const/4 v7, 0
invoke-static/range {v0 .. v7}, ${d}->${full}
move-result-object v0
if-ne v0, v9, :bad
invoke-virtual {v8}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v0
const-string v1, "load100%:05:05-07:10"
invoke-static {v0, v1}, ${c}->expect(Ljava/lang/String;Ljava/lang/String;)V
sget-object v0, ${c}->context:Landroid/content/Context;
move-object v1, v9
const-wide v2, ${start}L
move-wide v4, v2
const/16 v6, 0x81
invoke-static/range {v0 .. v6}, ${d}->formatDateRange(Landroid/content/Context;${f}JJI)${f}
move-result-object v0
if-ne v0, v9, :bad
invoke-virtual {v9}, ${f}->toString()Ljava/lang/String;
move-result-object v0
const-string v1, "load100%:05:05-07:1005:05"
invoke-static {v0, v1}, ${c}->expect(Ljava/lang/String;Ljava/lang/String;)V
sget-object v0, ${c}->context:Landroid/content/Context;
const-wide v1, ${start}L
const-wide v3, ${end}L
const/16 v5, 0x81
invoke-static/range {v0 .. v5}, ${d}->formatDateRange(Landroid/content/Context;JJI)Ljava/lang/String;
move-result-object v0
const-string v1, "05:05-07:10"
invoke-static {v0, v1}, ${c}->expect(Ljava/lang/String;Ljava/lang/String;)V
sget-object v0, ${c}->context:Landroid/content/Context;
const-wide v1, ${start}L
const/16 v3, 0x81
invoke-static {v0, v1, v2, v3}, ${d}->formatDateTime(Landroid/content/Context;JI)Ljava/lang/String;
move-result-object v0
const-string v1, "05:05"
invoke-static {v0, v1}, ${c}->expect(Ljava/lang/String;Ljava/lang/String;)V
return-void
' + date_range_failure('DateUtils formatter append identity'))
	source += method('private static errors()V', '
sget-object v0, ${c}->context:Landroid/content/Context;
new-instance v1, ${f}
invoke-direct {v1}, ${f}-><init>()V
invoke-virtual {v1}, ${f}->close()V
const-wide v2, ${start}L
move-wide v4, v2
const/16 v6, 0x81
const-string v7, "UTC"
:closed_start
invoke-static/range {v0 .. v7}, ${d}->${full}
:closed_end
goto :bad
.catch Ljava/util/FormatterClosedException; {:closed_start .. :closed_end} :closed
:closed
move-exception v0
new-instance v8, Lorg/vinix/bootstrap/FailRangeAppendable;
invoke-direct {v8}, Lorg/vinix/bootstrap/FailRangeAppendable;-><init>()V
sget-object v0, ${c}->context:Landroid/content/Context;
new-instance v1, ${f}
invoke-direct {v1, v8}, ${f}-><init>(Ljava/lang/Appendable;)V
const-wide v2, ${start}L
move-wide v4, v2
const/16 v6, 0x81
const-string v7, "UTC"
:io_start
invoke-static/range {v0 .. v7}, ${d}->${full}
:io_end
goto :bad
.catch Ljava/lang/AssertionError; {:io_start .. :io_end} :io
:io
move-exception v0
invoke-virtual {v0}, Ljava/lang/Throwable;->getCause()Ljava/lang/Throwable;
move-result-object v0
instance-of v1, v0, Ljava/io/IOException;
if-eqz v1, :bad
invoke-virtual {v0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v0
const-string v1, "range-append-failure"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
' + date_range_failure('DateUtils formatter exception contract'))
	os.write_file(dir + '/DateRangesProbe.smali', source)!
	mut failing := '.class public Lorg/vinix/bootstrap/FailRangeAppendable;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Appendable;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	for signature in ['append(Ljava/lang/CharSequence;)Ljava/lang/Appendable;',
		'append(Ljava/lang/CharSequence;II)Ljava/lang/Appendable;', 'append(C)Ljava/lang/Appendable;'] {
		failing += method('public ' + signature, 'new-instance v0, Ljava/io/IOException;\nconst-string v1, "range-append-failure"\ninvoke-direct {v0, v1}, Ljava/io/IOException;-><init>(Ljava/lang/String;)V\nthrow v0')
	}
	os.write_file(dir + '/FailRangeAppendable.smali', failing)!
}
