#!/bin/bash


while ! [ -f /etc/nginx/ssl/finished ]
do
  sleep 2
done

/usr/sbin/nginx -g "daemon off;"