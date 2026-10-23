import androidrun
import androidhost as ah
import os
import time

fn main() {
	assert os.args.len == 2
	path := 'build/android-maps/attempt234/google-maps/'
	mut monitor := androidrun.connect_monitor(path + 'qmp.sock', 20)!
	defer { monitor.close() }
	mut log := os.open_append(path + 'manual-timeline.log')!
	defer { log.close() }
	begin := time.now().str() + ' UTC+3 PACED-KEYS BEGIN text=' + os.args[1] + ' delay_ms=80\n'
	print(begin)
	log.write_string(begin)!
	for character in os.args[1].runes() {
		events := androidrun.key_events(character.str()) or { panic('unsupported key') }
		for event in events {
			monitor.command('input-send-event', {'events': ah.Value([event])})!
			time.sleep(80 * time.millisecond)
		}
	}
	end := time.now().str() + ' UTC+3 PACED-KEYS END\n'
	print(end)
	log.write_string(end)!
}
