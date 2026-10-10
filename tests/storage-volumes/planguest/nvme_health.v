// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn nvme_health_read(fd i32, disk u64, warning u8) {
	mut report := Health{}
	check(C.ioctl(fd,u64(0x56560005),unsafe { &report })==0,c'NVMe health query')
	check(report.version==1 && report.protocol==2 && report.disk_id==disk
		&& report.flags==if warning==0 { u64(15) } else { u64(31) },c'NVMe health header')
	check(report.data[0]==warning && (u16(report.data[1]) | (u16(report.data[2])<<8))!=0
		&& report.identify[24]!=0,c'NVMe identity and SMART log')
	for value in report.reserved { check(value==0,c'NVMe health reserved bytes') }
	check(C.ioctl(fd,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.EFAULT },c'NVMe bad health pointer')
}

fn nvme_health_check() {
	for index in 0 .. 2 {
		path := if index==0 { &char(c'/dev/nvme0n0') } else { &char(c'/dev/nvme1n0') }
		before := status(path)
		fd := C.open(path,C.O_RDONLY)
		check(fd>=0,c'open NVMe health disk')
		nvme_health_read(fd,before.disk_id,if index==0 { u8(0) } else { u8(8) })
		check(C.close(fd)==0,c'close NVMe health disk')
		after := status(path)
		check(before.reads==after.reads && before.writes==after.writes && before.flushes==after.flushes
			&& before.errors==after.errors,c'health leaves NVMe I/O counters unchanged')
		simple(c'health',path,unsafe { &char(nil) },if index==0 { 0 } else { 3 })
		tool(c'monitor',path,c'1',c'2',unsafe { &char(nil) },if index==0 { 0 } else { 3 })
		write_only:=C.open(path,C.O_WRONLY)
		check(write_only>=0 && C.ioctl(write_only,u64(0x56560005),voidptr(1))==-1
			&& unsafe { C.errno==C.EBADF } && C.close(write_only)==0,c'NVMe health write-only rejection')
	}
	part:=C.open(c'/dev/nvme0n0p0',C.O_RDONLY)
	check(part>=0 && C.ioctl(part,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.ENOTTY }
		&& C.close(part)==0,c'NVMe health partition rejection')
	C.printf(c'NVME HEALTH PASSED\n')
	C.printf(c'NVME MONITOR PASSED: controller telemetry, healthy and critical warning sessions\n')
}

fn nvme_health_cycles() {
	for index in 0 .. 2 {
		path := if index==0 { &char(c'/dev/nvme0n0') } else { &char(c'/dev/nvme1n0') }
		disk := status(path).disk_id
		fd := C.open(path,C.O_RDONLY)
		check(fd>=0,c'open repeated NVMe health disk')
		for _ in 0 .. 200 { nvme_health_read(fd,disk,if index==0 { u8(0) } else { u8(8) }) }
		check(C.close(fd)==0,c'close repeated NVMe health disk')
	}
}
