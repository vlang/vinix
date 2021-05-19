FROM ubuntu:latest
ENV TZ=Europe/London
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apt update
RUN export DEBIAN_FRONTEND=noninteractive
RUN apt install -yq build-essential git meson m4 texinfo python3 python3-pip util-linux wget mtools qemu-system-x86
RUN pip3 install xbstrap
COPY . .
RUN make distro
CMD ["/bin/bash"]