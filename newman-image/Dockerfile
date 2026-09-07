FROM postman/newman:5.3-alpine

RUN apk update && \
    apk upgrade && \
    apk add --no-cache curl zip iputils && \
    rm -rf /var/cache/apk/* 

RUN npm install -g newman-reporter-csvallinone

ENV NODE_PATH=/usr/local/lib/node_modules

WORKDIR /etc/newman

ENTRYPOINT ["newman"]