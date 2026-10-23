import os
import time

fn checked(args []string) string {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
	return r.output
}

fn main() {
	assert os.args.len >= 2 && os.args[1] in ['capture', 'click']
	b := 'build/android-maps/popup243/'
	serial := os.read_file(b + 'run-fixed/bootstrap-fixture/serial.log')!
	assert serial.contains('POPUP-MENU-GUEST-CLICK-READY')
	assert !serial.contains('ANDROID-WS-FAIL') && !serial.contains('java.lang.AssertionError')
	socket := os.abs_path(b + 'run-fixed/bootstrap-fixture/qmp.sock')
	if os.args[1] == 'capture' {
		println(checked(['build/android-run', 'screenshot', '--socket', socket, '--destination',
			os.abs_path(b + 'guest-ready.png')]))
		os.write_file(b + 'interaction.log', '${time.utc()} captured actual guest before click\n')!
	} else {
		assert os.args.len == 4
		assert os.is_file(b + 'guest-ready.png')
		println(checked(['build/android-run', 'input', 'click', os.args[2], os.args[3], '--socket',
			socket, '--settle', '0.2']))
		mut f := os.open_append(b + 'interaction.log')!
		f.writeln('${time.utc()} actual QMP input click x=${os.args[2]} y=${os.args[3]} socket=${socket}')!
		f.close()
		time.sleep(500 * time.millisecond)
		println(checked(['build/android-run', 'screenshot', '--socket', socket, '--destination',
			os.abs_path(b + 'guest-clicked.png')]))
		updated := os.read_file(b + 'run-fixed/bootstrap-fixture/serial.log')!
		assert updated.contains('POPUP-MENU-GUEST-ITEM-CLICK') && updated.contains('POPUP-MENU-PASS resources')
		assert !updated.contains('ANDROID-WS-FAIL') && !updated.contains('java.lang.AssertionError')
		mut done := os.open_append(b + 'interaction.log')!
		done.writeln('${time.utc()} real guest item callback and eighth delayed dismissal PASS')!
		done.close()
		println('POPUP-MENU INPUT PASS actual mouse click and final delayed dismissal')
	}
}
