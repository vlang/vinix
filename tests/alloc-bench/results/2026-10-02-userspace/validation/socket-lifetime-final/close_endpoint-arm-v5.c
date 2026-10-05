void unix__UnixSocket__close_endpoint(unix__UnixSocket* this) {
	klock__Lock__acquire(&this->l);
	if (this->closed) {
		klock__Lock__release(&this->l);
		return;
	}
	this->closed = true;
	this->listening = false;
	this->read_closed = true;
	this->write_closed = true;
	this->peer_finished = true;
	this->status &= ~file__pollout;
	this->status |= (file__pollin | file__pollhup) | file__pollerr;
	unix__UnixSocket* peer = this->peer;
	this->peer = NULL;
	unix__UnixSocket* target = this->dgram_target;
	this->dgram_target = NULL;
	Array queued = this->backlog;
	this->backlog = array_new(	sizeof(unix__UnixSocket*), 0, 0);
	Array pending = this->pending_fd_groups;
	this->pending_fd_groups = array_new(	sizeof(unix__PendingFdGroup), 0, 0);
	{
		array__free(&this->packet_lengths);
	}
	this->packet_lengths = __new_array_noscan(0, 0, sizeof(u64));
	{
		array__free(&this->datagrams);
	}
	this->datagrams = array_new(	sizeof(unix__DatagramSender), 0, 0);
	u8* data = this->data;
	this->data = NULL;
	this->capacity = 0;
	this->used = 0;
	this->read_ptr = 0;
	this->write_ptr = 0;
	klock__Lock__release(&this->l);
	if (data != NULL) {
		{
			v_free(data);
		}
	}
	{
		i64 __for_idx_0 = 0;
		for (; __for_idx_0 < pending.len; __for_idx_0++) {
			unix__PendingFdGroup group = *(unix__PendingFdGroup*)(array_get(pending, __for_idx_0));
			Array descriptors = group.fds;
			{
				i64 __for_idx_1 = 0;
				for (; __for_idx_1 < descriptors.len; __for_idx_1++) {
					file__FD** descriptor = (file__FD**)(array_get(descriptors, __for_idx_1));
					file__FD__unref(*descriptor);
				}
			}
			{
				array__free(&descriptors);
			}
		}
	}
	{
		array__free(&pending);
	}
	if (peer != NULL) {
		klock__Lock__acquire(&peer->l);
		peer->peer_finished = true;
		peer->status &= ~file__pollout;
		peer->status |= (file__pollin | file__pollhup) | file__pollerr;
		klock__Lock__release(&peer->l);
		event__trigger(&peer->event, false);
		unix__release(peer);
	}
	if (target != NULL) {
		unix__release(target);
	}
	{
		i64 __for_idx_2 = 0;
		for (; __for_idx_2 < queued.len; __for_idx_2++) {
			unix__UnixSocket** connection = (unix__UnixSocket**)(array_get(queued, __for_idx_2));
			unix__UnixSocket__close_endpoint(*connection);
			unix__release(*connection);
		}
	}
	{
		array__free(&queued);
	}
	event__trigger(&this->event, false);
}
