// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub const max_notifications = 64
pub const max_alarms = 64

pub enum Urgency {
	low
	normal
	critical
}

pub enum Focus {
	normal
	quiet
	focus
}

pub struct Notification {
pub mut:
	id        i64
	owner     Text
	key       Text
	title     Text
	body      Text
	action    Text
	created   i64
	urgency   Urgency
	progress  int = -1
	read      bool
	dismissed bool
}

pub struct Alarm {
pub mut:
	owner     Text
	key       Text
	title     Text
	due_epoch i64
	// A live countdown ignores wall-clock adjustments. Persisted alarms use
	// epoch time after a reboot, when a monotonic deadline has no meaning.
	due_monotonic  i64
	repeat_seconds int
	active         bool
}

pub struct Notifications {
pub mut:
	items          [max_notifications]Notification
	count          int
	alarms         [max_alarms]Alarm
	alarm_count    int
	next_id        i64 = 1
	mode           Focus
	focus_until    i64
	allow_critical bool = true
}

pub fn (mut n Notifications) post(owner string, key string, title string, body string, urgency Urgency, progress int, action string, now i64) !i64 {
	if !identifier(owner) || key.len > 128 || title.len == 0 || title.len > 128 || progress < -1 || progress > 100 {
		return error('invalid notification')
	}
	mut item := Notification{ owner: text(owner)!, key: text(key)!, title: text(title)!, body: text(body)!, action: text(action)!, created: now, urgency: urgency, progress: progress }
	for i in 0 .. n.count {
		if key.len > 0 && !n.items[i].dismissed && n.items[i].owner.str() == owner && n.items[i].key.str() == key {
			item.id = n.items[i].id
			item.read = n.items[i].read
			n.items[i] = item
			return item.id
		}
	}
	if n.next_id >= 9223372036854775806 { return error('notification IDs exhausted') }
	item.id = n.next_id
	n.next_id++
	if n.count == max_notifications {
		for i in 1 .. n.count { n.items[i - 1] = n.items[i] }
		n.count--
	}
	n.items[n.count] = item
	n.count++
	return item.id
}

pub fn (n &Notifications) show_banner(item Notification, now i64) bool {
	if item.read || item.dismissed { return false }
	mode := if n.focus_until > 0 && now >= n.focus_until { Focus.normal } else { n.mode }
	return mode == .normal || (n.allow_critical && item.urgency == .critical)
}

pub fn (mut n Notifications) schedule(owner string, key string, title string, epoch i64, monotonic i64, repeat_seconds int) ! {
	if !identifier(owner) || key.len == 0 || key.len > 128 || title.len == 0 || title.len > 128 || epoch <= 0 || repeat_seconds < 0 || repeat_seconds > 31536000 {
		return error('invalid alarm')
	}
	item := Alarm{ owner: text(owner)!, key: text(key)!, title: text(title)!, due_epoch: epoch, due_monotonic: monotonic, repeat_seconds: repeat_seconds, active: true }
	mut slot := -1
	for i in 0 .. n.alarm_count {
		if n.alarms[i].owner.str() == owner && n.alarms[i].key.str() == key {
			slot = i
			break
		}
		if !n.alarms[i].active { slot = i }
	}
	if slot < 0 {
		if n.alarm_count == max_alarms { return error('too many alarms') }
		slot = n.alarm_count
		n.alarm_count++
	}
	n.alarms[slot] = item
}

pub fn (mut n Notifications) cancel(owner string, key string) bool {
	for i in 0 .. n.alarm_count {
		if n.alarms[i].owner.str() == owner && n.alarms[i].key.str() == key {
			n.alarms[i].active = false
			return true
		}
	}
	return false
}

pub fn (mut n Notifications) tick(epoch i64, monotonic i64) bool {
	mut changed := false
	if n.focus_until > 0 && epoch >= n.focus_until {
		n.mode = .normal
		n.focus_until = 0
		changed = true
	}
	for i in 0 .. n.alarm_count {
		a := unsafe { &n.alarms[i] }
		if !a.active || (if a.due_monotonic > 0 {
			monotonic < a.due_monotonic
		} else {
			epoch < a.due_epoch
		}) {
			continue
		}
		n.post(a.owner.str(), a.key.str(), a.title.str(), 'Alarm due', .critical, -1, '', epoch) or { continue }
		changed = true
		if a.repeat_seconds == 0 {
			n.alarms[i].active = false
		} else {
			// Missed repeats coalesce; never emit a burst after suspend/reboot.
			missed := if epoch >= a.due_epoch {
				(epoch - a.due_epoch) / a.repeat_seconds + 1
			} else {
				i64(1)
			}
			n.alarms[i].due_epoch = a.due_epoch + missed * a.repeat_seconds
			n.alarms[i].due_monotonic = monotonic + (n.alarms[i].due_epoch - epoch) * 1000
		}
	}
	return changed
}

pub fn (mut n Notifications) dismiss(id i64) bool {
	for i in 0 .. n.count {
		if n.items[i].id == id {
			n.items[i].read = true
			n.items[i].dismissed = true
			return true
		}
	}
	return false
}

// An application may withdraw only its own keyed notification. Compositor
// dismissal remains the separate operation that accepts a global numeric ID.
pub fn (mut n Notifications) withdraw(owner string, key string) bool {
	for i in 0 .. n.count {
		if !n.items[i].dismissed && n.items[i].owner.str() == owner && n.items[i].key.str() == key {
			n.items[i].read = true
			n.items[i].dismissed = true
			return true
		}
	}
	return false
}

pub fn (n &Notifications) encode() string {
	mut w := &Writer{}
	defer { unsafe { free(w) } }
	w.add('vinix-notifications\t1\t')
	w.number(n.next_id)
	w.add('\t')
	w.number(int(n.mode))
	w.add('\t')
	w.number(n.focus_until)
	w.add('\t')
	w.number(int(n.allow_critical))
	w.add('\n')
	for i in 0 .. n.count {
		a := unsafe { &n.items[i] }
		w.add('notice\t')
		w.number(a.id)
		for t in [&a.owner, &a.key, &a.title, &a.body, &a.action]! {
			w.add('\t')
			w.field(t.str())
		}
		for value in [a.created, i64(a.urgency), i64(a.progress), i64(int(a.read)),
			i64(int(a.dismissed))]! {
			w.add('\t')
			w.number(value)
		}
		w.add('\n')
	}
	for i in 0 .. n.alarm_count {
		a := unsafe { &n.alarms[i] }
		w.add('alarm')
		for t in [&a.owner, &a.key, &a.title]! {
			w.add('\t')
			w.field(t.str())
		}
		w.add('\t')
		w.number(a.due_epoch)
		w.add('\t')
		w.number(a.repeat_seconds)
		w.add('\t')
		w.number(int(a.active))
		w.add('\n')
	}
	return w.finish()
}

pub fn decode_notifications(record string) !Notifications {
	if record.len == 0 || record.len > 256 * 1024 {
		return error('invalid notification record size')
	}
	// References into inline records can make V move a value local onto the
	// heap. Own the parser's scratch storage until the result is copied out.
	mut n := &Notifications{}
	defer { unsafe { free(n) } }
	mut start := 0
	mut header := false
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		if end == start {
			start = end + 1
			continue
		}
		f := fields(unsafe { tos(record.str + start, end - start) })!
		start = end + 1
		if !header {
			if f.count != 6 || f.values[0] != 'vinix-notifications' || f.values[1] != '1' {
				return error('invalid notification header')
			}
			n.next_id = number(f.values[2], 1, 9223372036854775806)!
			n.mode = unsafe { Focus(number(f.values[3], 0, 2)!) }
			n.focus_until = number(f.values[4], 0, 9223372036854775)!
			n.allow_critical = number(f.values[5], 0, 1)! != 0
			header = true
			continue
		}
		if f.values[0] == 'notice' {
			if f.count != 12 || n.count == max_notifications {
				return error('invalid notification record')
			}
			n.items[n.count] = Notification{ id: number(f.values[1], 1, n.next_id - 1)!, owner: unfield(f.values[2])!, key: unfield(f.values[3])!, title: unfield(f.values[4])!, body: unfield(f.values[5])!, action: unfield(f.values[6])! }
			mut a := unsafe { &n.items[n.count] }
			if !identifier(a.owner.str()) || a.title.len == 0 || a.title.len > 128 {
				return error('invalid notification owner/title')
			}
			a.created = number(f.values[7], 0, 9223372036854775)!
			a.urgency = unsafe { Urgency(number(f.values[8], 0, 2)!) }
			a.progress = int(number(f.values[9], -1, 100)!)
			a.read = number(f.values[10], 0, 1)! != 0
			a.dismissed = number(f.values[11], 0, 1)! != 0
			for i in 0 .. n.count {
				if n.items[i].id == a.id { return error('duplicate notification') }
			}
			n.count++
		} else if f.values[0] == 'alarm' {
			if f.count != 7 || n.alarm_count == max_alarms { return error('invalid alarm record') }
			n.alarms[n.alarm_count] = Alarm{ owner: unfield(f.values[1])!, key: unfield(f.values[2])!, title: unfield(f.values[3])! }
			mut a := unsafe { &n.alarms[n.alarm_count] }
			if !identifier(a.owner.str()) || a.key.len == 0 || a.key.len > 128
				|| a.title.len == 0 || a.title.len > 128 { return error('invalid alarm') }
			for i in 0 .. n.alarm_count {
				if n.alarms[i].owner.str() == a.owner.str() && n.alarms[i].key.str() == a.key.str() {
					return error('duplicate alarm')
				}
			}
			a.due_epoch = number(f.values[4], 1, 9223372036854775)!
			a.repeat_seconds = int(number(f.values[5], 0, 31536000)!)
			a.active = number(f.values[6], 0, 1)! != 0
			n.alarm_count++
		} else {
			return error('unknown notification record')
		}
	}
	if !header { return error('missing notification header') }
	return *n
}
