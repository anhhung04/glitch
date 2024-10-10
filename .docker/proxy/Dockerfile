FROM ubuntu:22.04

USER root
ARG HOSTNAME

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    net-tools \
    iputils-ping \
    iproute2 \
    iptables \
    openssh-server \
    ufw \
    htop \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY ./entrypoint.sh /entrypoint.sh

RUN mkdir /var/run/sshd
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

RUN ufw default allow in \
    && ufw --force enable

RUN echo -n "root:root" | chpasswd
RUN hostnamectl set-hostname $HOSTNAME

EXPOSE 22

ENTRYPOINT [ "/entrypoint.sh" ]