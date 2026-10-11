// The production ioctl dispatcher now includes the health read path. This
// independent host device supplies that interface without changing Disk or
// the existing volume assertions.
module fs

import errno
import file
import resource

fn test_health_dispatch_read_access_and_output_fault() {
	mut device := &HealthDisk{}
	boxed := &resource.Resource(device)
	mut descriptor := file.FD{ handle: &file.Handle{ resource: boxed, flags: resource.o_rdonly } }
	mut snapshot := resource.BlockHealth{}
	assert storage_ioctl(mut descriptor, resource.block_health_ioctl, unsafe { &snapshot }) or { panic('health') } == 0
	assert snapshot.version == 1 && snapshot.protocol == resource.health_ata && snapshot.disk_id == 42
	assert snapshot.flags == resource.health_supported
	if _ := storage_ioctl(mut descriptor, resource.block_health_ioctl, unsafe { nil }) {
		assert false
	}
	assert errno.get() == errno.efault
	descriptor.handle.flags = resource.o_wronly
	if _ := storage_ioctl(mut descriptor, resource.block_health_ioctl, unsafe { &snapshot }) {
		assert false
	}
	assert errno.get() == errno.ebadf
	plain := &resource.Resource(LogicalVolume{})
	descriptor.handle.resource = plain
	descriptor.handle.flags = resource.o_rdonly
	if _ := storage_ioctl(mut descriptor, resource.block_health_ioctl, unsafe { &snapshot }) {
		assert false
	}
	assert errno.get() == errno.enotty
}
