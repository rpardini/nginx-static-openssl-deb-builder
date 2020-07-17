FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update
RUN apt -y install build-essential eatmydata dh-systemd quilt libpcre3-dev zlib1g-dev git lsb-release wget

ADD build_nginx_openssl_static_deb.sh /tmp/build_nginx_tls13_ubuntu.sh
RUN chmod +x /tmp/build_nginx_tls13_ubuntu.sh
RUN /tmp/build_nginx_tls13_ubuntu.sh

