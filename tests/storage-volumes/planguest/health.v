// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

struct Health {
mut:
	version u64
	protocol u64
	flags u64
	disk_id u64
	reserved [4]u64
	identify [512]u8
	data [512]u8
}

@[direct_array_access]
fn health_read(fd i32, disk u64) {
	mut report:=Health{}
	$if amd64 {
		check(C.ioctl(fd,u64(0x56560005),unsafe { &report })==0, c'AHCI health query')
		check(report.version==1 && report.protocol==1 && report.flags==15 && report.disk_id==disk, c'healthy ATA report')
		mut sum:=u32(0)
		for value in report.data { sum+=value }
		check(sum & 255==0 && report.data[0]==1 && report.data[2]!=0, c'ATA data checksum and attributes')
		for value in report.reserved { check(value==0,c'health ABI reserved bytes') }
	} $else {
		check(C.ioctl(fd,u64(0x56560005),unsafe { &report })==-1 && unsafe { C.errno==C.ENOTTY }, c'unsupported VirtIO health')
	}
}

fn health_check(parent &char) {
	fd:=C.open(parent,C.O_RDONLY)
	check(fd>=0,c'open physical health disk')
	disk:=status(parent).disk_id
	health_read(fd,disk)
	$if amd64 {
		check(C.ioctl(fd,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.EFAULT },c'bad health output pointer')
	}
	check(C.close(fd)==0,c'close health disk')
	write_only:=C.open(parent,C.O_WRONLY)
	check(write_only>=0 && C.ioctl(write_only,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.EBADF }
		&& C.close(write_only)==0,c'health rejects write-only descriptor')
	regular:=C.open(c'/root/health-regular',C.O_RDONLY | C.O_CREAT,u32(0o600))
	check(regular>=0 && C.ioctl(regular,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.ENOTTY }
		&& C.close(regular)==0,c'health rejects regular resource')
	$if amd64 {
		part:=C.open(c'/dev/sd0-0',C.O_RDONLY)
		check(part>=0 && C.ioctl(part,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.ENOTTY }
			&& C.close(part)==0,c'health rejects partition')
	}
	view:=C.open(c'/dev/mapper/vinix2',C.O_RDONLY)
	check(view>=0 && C.ioctl(view,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.ENOTTY }
		&& C.close(view)==0,c'health rejects volume')
	simple(c'health',parent,unsafe { &char(nil) },$if amd64 { 0 } $else { 1 })
	tool(c'monitor', parent, c'1', c'2', unsafe { &char(nil) }, $if amd64 { 0 } $else { 4 })
	tool(c'monitor', c'/dev/mapper/vinix2', c'1', c'1', unsafe { &char(nil) }, 4)
	tool(c'monitor', c'/root/health-regular', c'1', c'1', unsafe { &char(nil) }, 1)
	C.printf(c'STORAGE MONITOR PASSED: physical samples, volume health unavailable, regular file rejected\n')
	// Repeat only the query with one retained descriptor. Its success and
	// failure paths must not retain a kernel object or promote the report.
	C.printf(c'HEALTH QUERY PASSED\n')
}

fn health_cycles(parent &char) {
	fd:=C.open(parent,C.O_RDONLY)
	check(fd>=0,c'open repeated health disk')
	disk:=status(parent).disk_id
	for i in 0 .. 200 {
		health_read(fd,disk)
		$if amd64 {
			check(C.ioctl(fd,u64(0x56560005),voidptr(1))==-1 && unsafe { C.errno==C.EFAULT },c'repeated bad health pointer')
		}
	}
	check(C.close(fd)==0,c'close repeated health disk')
}
