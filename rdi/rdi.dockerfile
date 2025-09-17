FROM redislabs/redis-di-cli:v0.118.0

USER root:root

RUN microdnf install openssh-server

RUN adduser  labuser && \
    usermod -aG wheel labuser

RUN ssh-keygen -A

USER labuser:labuser

COPY from-repo/scripts /scripts

USER root:root

RUN python3 -m pip install -r /scripts/generate-load-requirements.txt

#RUN echo '\n\nlabuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
