FROM openjdk

# Define application names
ENV APP_NAME=reactivems
ENV APP_VERSION=1.0.0

ENV APP_NAME_VERSION=${APP_NAME}-${APP_VERSION}

VOLUME /tmp

ADD http://engci-maven.cisco.com/artifactory/oneidentityhub-group/com/cisco/oneidentity/iam/${APP_NAME}/${APP_VERSION}/${APP_NAME_VERSION}.jar boot.jar

RUN sh -c 'touch /boot.jar'

ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","/boot.jar"]