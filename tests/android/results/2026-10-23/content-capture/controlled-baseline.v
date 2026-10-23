import os

fn checked(args []string) ! {
 r := os.exec(args)
 if r.exit_code != 0 { return error(r.output) }
}

fn main() {
 assert os.args.len == 2, 'usage: controlled-baseline <fresh output directory>'
 dir := os.abs_path(os.args[1])
 os.mkdir_all(dir)!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 tools := os.abs_path('build/android-framework/tools')
 fixed := os.abs_path('build/android-maps/framework221-content-capture/api-impl.jar')
 checked([java, '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', fixed, '-o', dir + '/smali'])!
 file := dir + '/smali/android/view/View.smali'
 text := os.read_file(file)!
 signature := '.method public getContentCaptureSession()Landroid/view/contentcapture/ContentCaptureSession;'
 start := text.index(signature) or { panic('missing fixed getter') }
 end := start + (text[start..].index('.end method') or { panic('unterminated getter') }) + '.end method'.len
 os.write_file(file, text[..start] + text[end..])!
 checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', dir + '/smali', '-o', dir + '/classes.dex'])!
 os.cp(fixed, dir + '/baseline.jar')!
 checked(['zip', '-q', '-j', dir + '/baseline.jar', dir + '/classes.dex'])!
}
