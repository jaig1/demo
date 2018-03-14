FROM containers.cisco.com/oneidentity/centos7-java:v3

# Install prepare infrastructure
RUN yum -y install openssl

# Define application names
ENV APP_NAME=reactive-spring-sample
ENV APP_VERSION=1.1.9
#ENV APP_BRANCH=SNAPSHOT

#ENV APP_NAME_VERSION=${APP_NAME}-${APP_VERSION}-${APP_BRANCH}
ENV APP_NAME_VERSION=${APP_NAME}-${APP_VERSION}

WORKDIR /app

#ADD http://engci-maven.cisco.com/artifactory/oneidentityhub-group/com/cisco/oneidentity/iam/${APP_NAME}/${APP_VERSION}-${APP_BRANCH}/${APP_NAME_VERSION}.jar boot.jar
ADD http://engci-maven.cisco.com/artifactory/oneidentityhub-group/com/cisco/oneidentity/iam/${APP_NAME}/${APP_VERSION}/${APP_NAME_VERSION}.jar boot.jar

ADD /conf conf

ADD /src/main/resources/application.yaml /app/

RUN chmod a+x /app/boot.jar && \
    chmod a+rw /app/boot.jar
    
RUN chmod a+x /app/application.yaml 

RUN chgrp -R 0 /app/ && chmod -R g+rwX /app/

ADD /conf/bin/container-limits.sh /app/
ADD /conf/bin/start.sh /app/

RUN chmod a+x /app/container-limits.sh
RUN chmod a+x /app/start.sh && chmod a+rwx /app

ADD /conf/supervisor/* /etc/supervisor/conf.d/

ADD /conf/consul/* /etc/consul/

EXPOSE 9443

