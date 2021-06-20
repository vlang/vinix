FROM ubuntu:20.04 AS base

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y install \
    build-essential git curl meson m4 texinfo python3 python3-pip

RUN pip3 install xbstrap

FROM base AS user
ARG USER=1000

RUN useradd -ms /bin/bash vinix_buildenv -u $USER
USER vinix_buildenv
WORKDIR /home/vinix_buildenv

CMD ["bash"]
