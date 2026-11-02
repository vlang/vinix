// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const pass_marker = 'STABLE-DISPLAY-PASS physical-size window-size fresh-points mutation-isolation'
const fail_marker = 'STABLE-DISPLAY-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn checks_source() string {
	return method('private static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-ne p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static point(Landroid/graphics/Point;IILjava/lang/String;)V', 1, '
iget v0, p0, Landroid/graphics/Point;->x:I
invoke-static {v0, p1, p3}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, Landroid/graphics/Point;->y:I
invoke-static {v0, p2, p3}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

// Test expectations come from the independent guest/surface configuration in
// the signed builder argv. Neither a fallback dimension nor Display globals
// supply the expected physical size. Scratch v7..v9 leave the saved Points live.
fn check_point(register string, width int, height int, label string) string {
	return 'const/16 v7, ${width}\nconst/16 v8, ${height}\nconst-string v9, "${label}"\ninvoke-static {${register}, v7, v8, v9}, ${main_type}->point(Landroid/graphics/Point;IILjava/lang/String;)V\n'
}

fn probe_source(sizes []int) string {
	physical_width, physical_height := sizes[0], sizes[1]
	window_width, window_height := sizes[2], sizes[3]
	mut body := '
const-string v9, "display"
invoke-virtual {p0, v9}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/hardware/display/DisplayManager;
const/4 v9, 0
invoke-virtual {v0, v9}, Landroid/hardware/display/DisplayManager;->getDisplay(I)Landroid/view/Display;
move-result-object v1
new-instance v2, Landroid/graphics/Point;
invoke-direct {v2}, Landroid/graphics/Point;-><init>()V
invoke-virtual {v1, v2}, Landroid/view/Display;->getRealSize(Landroid/graphics/Point;)V
'
	body += check_point('v2', window_width, window_height, 'real-size API must retain configured app-surface dimensions')
	body += '
new-instance v3, Landroid/util/DisplayMetrics;
invoke-direct {v3}, Landroid/util/DisplayMetrics;-><init>()V
invoke-virtual {v1, v3}, Landroid/view/Display;->getRealMetrics(Landroid/util/DisplayMetrics;)V
iget v7, v3, Landroid/util/DisplayMetrics;->widthPixels:I
iget v8, v2, Landroid/graphics/Point;->x:I
const-string v9, "real metrics width must match unchanged app-surface API"
invoke-static {v7, v8, v9}, ${main_type}->equal(IILjava/lang/String;)V
iget v7, v3, Landroid/util/DisplayMetrics;->heightPixels:I
iget v8, v2, Landroid/graphics/Point;->y:I
const-string v9, "real metrics height must match unchanged app-surface API"
invoke-static {v7, v8, v9}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, Landroid/hardware/display/DisplayManager;->getStableDisplaySize()Landroid/graphics/Point;
move-result-object v4
'
	body += check_point('v4', physical_width, physical_height, 'stable size must match independently pinned physical desktop')
	body += '
invoke-virtual {v0}, Landroid/hardware/display/DisplayManager;->getStableDisplaySize()Landroid/graphics/Point;
move-result-object v5
const-string v9, "each stable-size call must return a fresh Point"
invoke-static {v4, v5, v9}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
'
	body += check_point('v5', physical_width, physical_height, 'equal-valued Point results must both contain physical dimensions')
	body += '
const/16 v7, -71
const/16 v8, -72
invoke-virtual {v4, v7, v8}, Landroid/graphics/Point;->set(II)V
'
	body += check_point('v5', physical_width, physical_height, 'mutating first return must not change second live result')
	body += '
invoke-virtual {v0}, Landroid/hardware/display/DisplayManager;->getStableDisplaySize()Landroid/graphics/Point;
move-result-object v6
const-string v9, "third stable result must not reuse first Point"
invoke-static {v4, v6, v9}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v9, "third stable result must not reuse second Point"
invoke-static {v5, v6, v9}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
'
	body += check_point('v6', physical_width, physical_height, 'mutating a returned Point must not poison later queries')
	body += check_point('v4', -71, -72, 'later queries must not rewrite an earlier caller-owned Point')
	body += '
const/16 v7, -81
const/16 v8, -82
invoke-virtual {v6, v7, v8}, Landroid/graphics/Point;->set(II)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v7
const-string v9, "display"
invoke-virtual {v7, v9}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v7
check-cast v7, Landroid/hardware/display/DisplayManager;
invoke-virtual {v7}, Landroid/hardware/display/DisplayManager;->getStableDisplaySize()Landroid/graphics/Point;
move-result-object v7
const-string v9, "application-context result must not alias existing live Point"
invoke-static {v5, v7, v9}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v4, v7, v9}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v6, v7, v9}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
move-object v0, v7
'
	body += check_point('v0', physical_width, physical_height, 'application-context query must retain physical dimensions')
	body += check_point('v5', physical_width, physical_height, 'later mutation must not change retained second result')
	body += check_point('v6', -81, -82, 'cross-context query must not rewrite caller-owned third Point')
	body += check_point('v4', -71, -72, 'cross-context query must not rewrite caller-owned first Point')
	body += '
invoke-virtual {v1, v2}, Landroid/view/Display;->getRealSize(Landroid/graphics/Point;)V
'
	body += check_point('v2', window_width, window_height, 'stable queries must leave app-surface dimensions unchanged')
	body += '
invoke-virtual {v1, v3}, Landroid/view/Display;->getRealMetrics(Landroid/util/DisplayMetrics;)V
iget v7, v3, Landroid/util/DisplayMetrics;->widthPixels:I
iget v8, v2, Landroid/graphics/Point;->x:I
const-string v9, "stable queries must leave real metrics width unchanged"
invoke-static {v7, v8, v9}, ${main_type}->equal(IILjava/lang/String;)V
iget v7, v3, Landroid/util/DisplayMetrics;->heightPixels:I
iget v8, v2, Landroid/graphics/Point;->y:I
const-string v9, "stable queries must leave real metrics height unchanged"
invoke-static {v7, v8, v9}, ${main_type}->equal(IILjava/lang/String;)V
return-void'
	return method('private static probe(Landroid/content/Context;)V', 10, body)
}

fn main_source(sizes []int) string {
	return '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + probe_source(sizes) + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Stable physical display-size contracts passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2')
}

fn fixture_sources(sizes []int) map[string]string {
	return {'org/vinix/bootstrap/Main.smali': main_source(sizes)}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali']
}
