FROM redislabs/redis:7.22.0-241.focal

USER root:root

COPY ./redis/init_script.sh /tmp/init_script.sh

RUN apt-get update && \
    apt-get install -y git && \
    apt-get install -y openssh-server && \
    apt-get install -y jq

RUN adduser --disabled-password --gecos "Lab User,,," labuser && \
    usermod -aG redislabs,sudo labuser

RUN echo '\n\nlabuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
