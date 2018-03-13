FROM mamohr/centos-java

# Install prepare infrastructure
RUN yum -y install tar unzip wget less openssl epel-release
RUN yum -y install nginx

# Define application names
ENV APP_NAME=reactive-spring-sample
ENV APP_VERSION=1.0.0

ENV APP_NAME_VERSION=${APP_NAME}-${APP_VERSION}


WORKDIR /app

ADD http://engci-maven.cisco.com/artifactory/oneidentityhub-group/com/cisco/oneidentity/iam/${APP_NAME}/${APP_VERSION}/${APP_NAME_VERSION}.jar boot.jar


ADD ${APP_NAME}/conf conf

RUN chmod a+x /app/boot.jar && \
    chmod a+rw /app/boot.jar

RUN chgrp -R 0 /app/ && chmod -R g+rwX /app/

ADD ${APP_NAME}/conf/bin/start.sh /app/
ADD ${APP_NAME}/conf/bin/startnginx.sh /app/

RUN chmod a+x /app/start.sh && chmod a+rwx /app && chmod a+x /app/startnginx.sh

ADD ${APP_NAME}/conf/supervisor/* /etc/supervisor/conf.d/

ADD ${APP_NAME}/conf/consul/* /etc/consul/

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


ADD ${APP_NAME}/conf/nginx/app.conf /etc/nginx/conf/app.conf
ADD ${APP_NAME}/conf/nginx/nginx.conf /etc/nginx/nginx.conf

EXPOSE 9443