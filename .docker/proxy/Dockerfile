FROM ubuntu:22.04

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
    conntrack

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
RUN echo -n "root:root" | chpasswd

EXPOSE 22

ENTRYPOINT [ "/entrypoint.sh" ]