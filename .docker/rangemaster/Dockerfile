FROM nginx:alpine3.20

RUN apk update
RUN apk upgrade

# Install curl and jq
RUN apk add curl jq python3 nano bash nginx

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d /etc/nginx/conf.d

CMD ["nginx", "-g", "daemon off;"]