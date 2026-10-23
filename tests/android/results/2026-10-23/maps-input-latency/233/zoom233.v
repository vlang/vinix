import androidrun
import androidhost as ah
import os
import time

fn main() {
	assert os.args.len == 3
	x := os.args[1].i64()
	y := os.args[2].i64()
	path := 'build/android-maps/attempt233/google-maps/'
	mut monitor := androidrun.connect_monitor(path + 'qmp.sock', 20)!
	defer { monitor.close() }
	mut log := os.open_append(path + 'manual-timeline.log')!
	defer { log.close() }
	begin := time.now().str() + ' UTC+3 DOUBLE-TAP BEGIN x=' + x.str() + ' y=' + y.str() + '\n'
	print(begin)
	log.write_string(begin)!
	monitor.command('input-send-event', {'events': ah.Value(androidrun.move_events(x, y, 1024, 768))})!
	time.sleep(100 * time.millisecond)
	for _ in 0 .. 2 {
		monitor.command('input-send-event', {'events': ah.Value(androidrun.button_events(true))})!
		time.sleep(80 * time.millisecond)
		monitor.command('input-send-event', {'events': ah.Value(androidrun.button_events(false))})!
		time.sleep(80 * time.millisecond)
	}
	end := time.now().str() + ' UTC+3 DOUBLE-TAP END\n'
	print(end)
	log.write_string(end)!
}
