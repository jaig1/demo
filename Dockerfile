FROM mamohr/centos-java

# Install prepare infrastructure
RUN yum -y install tar unzip wget less openssl epel-release
RUN yum -y install nginx

# Define application names
ENV APP_NAME=service-iam-search-spring
ENV APP_VERSION=1.2.3
ENV APP_BRANCH=SNAPSHOT

ENV APP_NAME_VERSION=${APP_NAME}-${APP_VERSION}-${APP_BRANCH}


WORKDIR /app

ADD /target/reactivems-1.0.0.jar boot.jar

ADD /conf conf

RUN chmod a+x /app/boot.jar && \
    chmod a+rw /app/boot.jar

RUN chgrp -R 0 /app/ && chmod -R g+rwX /app/

ADD /conf/bin/start.sh /app/
ADD /conf/bin/startnginx.sh /app/

RUN chmod a+x /app/start.sh && chmod a+rwx /app && chmod a+x /app/startnginx.sh

ADD /conf/supervisor/* /etc/supervisor/conf.d/

ADD /conf/consul/* /etc/consul/

RUN mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig \
&&	mkdir /etc/nginx/conf \
&&	mkdir /etc/nginx/ssl \
&&  mkdir /app/nginx \
&&  mkdir /app/nginx/tmp \
&&  mkdir /app/nginx/tmp/fastcgi_temp \
&&  mkdir /app/nginx/tmp/proxy_temp \
&&  mkdir /app/nginx/tmp/scgi_temp \
&&  mkdir /app/nginx/tmp/uwsgi_temp \
&&  mkdir /app/nginx/tmp/client_body_temp \
&&  chmod 777 /app/nginx \
&&  chmod 777 /etc/nginx/ssl


ADD /conf/nginx/app.conf /etc/nginx/conf/app.conf
ADD /conf/nginx/nginx.conf /etc/nginx/nginx.conf

EXPOSE 9443


