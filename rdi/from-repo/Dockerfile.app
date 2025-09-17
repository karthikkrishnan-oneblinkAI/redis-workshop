FROM node:18-alpine

RUN mkdir -p /app

COPY app/package.json /

RUN yarn install

RUN echo "#! /bin/sh" >> /entrypoint && \
    echo "mkdir -p /app/node_modules" >> /entrypoint && \
    echo "mount -o bind /node_modules /app/node_modules" >> /entrypoint && \
    echo "while ! nc -z ${REDIS_TARGET_DB_HOST:-redis} ${REDIS_TARGET_DB_PORT:-12000}; do" >> /entrypoint && \
    echo "  echo 'Waiting for redis...'" >> /entrypoint && \
    echo "  sleep 3" >> /entrypoint && \
    echo "done" >> /entrypoint && \
    echo "sleep 5" >> /entrypoint && \
    echo "exec \"\$@\"" >> /entrypoint && \
    echo "" >> /entrypoint && \
    chmod +x /entrypoint

WORKDIR /app/

EXPOSE 8081

ENTRYPOINT ["/entrypoint"]
CMD node DemoServer.js
