// Independent host device for the production health interface.
module fs

import event.eventstruct
import klock
import resource
import stat

struct HealthDisk {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut disk HealthDisk) block_health() ?resource.BlockHealth {
	return resource.BlockHealth{ protocol: resource.health_ata, flags: resource.health_supported, disk_id: 42 }
}

fn (mut disk HealthDisk) grow(_ voidptr, _ u64) ? { return none }

fn (mut disk HealthDisk) read(_ voidptr, _ voidptr, _ u64, _ u64) ?i64 { return none }

fn (mut disk HealthDisk) write(_ voidptr, _ voidptr, _ u64, _ u64) ?i64 { return none }

fn (mut disk HealthDisk) ioctl(_ voidptr, _ u64, _ voidptr) ?int { return none }

fn (mut disk HealthDisk) unref(_ voidptr) ? { return none }

fn (mut disk HealthDisk) link(_ voidptr) ? { return none }

fn (mut disk HealthDisk) unlink(_ voidptr) ? { return none }

fn (mut disk HealthDisk) mmap(_ voidptr, _ u64, _ int) voidptr { return unsafe { nil } }
