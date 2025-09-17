FROM tsl0922/ttyd:alpine

USER root

RUN apk add sudo && \
    apk add --no-cache --update openssh-keygen openssh 

#RUN adduser --disabled-password -g "Lab User,,," labuser wheel 

#RUN echo '\n\nlabuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/labuser && chmod 0440 /etc/sudoers.d/labuser

#USER labuser:labuser

COPY term.bashrc /root/.bashrc

#RUN echo 'alias n1-status="ssh -t re-n1 /opt/redislabs/bin/rladmin status"' >> ~labuser/.ashrc

#CMD node bin
#RUN apt update && \
#    apt install -y git

#USER root:root

#ENTRYPOINT ["/sbin/tini" "--"]

#CMD ttyd bash
#CMD ttyd -u 1000 -g 1000 bash
