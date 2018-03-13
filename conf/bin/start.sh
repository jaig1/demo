#!/bin/bash
export HOME=/app
echo "Starting $APP_NAME"

# return 1 if the value is ok
check_null () {
  if [ -z "$1" ]; then
    return 1
  elif [ "$1" == "null" ]; then
    return 1
  else
    return 0
  fi
}

# retry_get url vault_token  jq_path retry_times
retry_get () {
  unset RESP
  for i in $(seq 1 $4); do
    echo "Trying to get for the #${i} time: ${1}"
    RESP=`curl -XGET -H 'x-vault-token: '${2} ${1} | jq -c -r ${3}`
    check_null ${RESP}
    if [ $? -eq 0 ] ; then
      return 0
    else
      echo "Empty response: ${RESP}"
    fi
    sleep 5
  done
  echo "Failed to get. Exit."
  exit 1
}

PID_LOC=/app/$APP_NAME_VERSION/RUNNING_PID

if [ -e $PID_LOC ]; then
	PID=cat $PID_LOC;
	ps -p $PID>/dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Remove obsolete RUNNING_PID file: $PID"
		rm -f $PID_LOC
		sleep 15s
	fi
fi

echo "Calculating Container Limits"
. /app/container-limits.sh

echo "Calculating JVM MEMORY"
JVM_MEMORY=$(($CONTAINER_MAX_MEMORY / 4 * 3))
echo "JVM Memory is $JVM_MEMORY"

#Define where to put the certificate
SECRET_DIR=/app/secret

#Define where to store the key, csr, signed cert and ca
CERT_KEY=$SECRET_DIR/${VAULT_SERVICE_NAME}.key
CSR_CERT=$SECRET_DIR/${VAULT_SERVICE_NAME}.csr
SIGN_CERT=$SECRET_DIR/${VAULT_SERVICE_NAME}.pem
CA_CHAIN=$SECRET_DIR/cachain.pem

#Define where to store the pkcs12 keystore
SECRET_P12=$SECRET_DIR/keystore.p12

#Generate a random keystore password
KEYSTORE_PASSWORD=$(date | md5sum | base64)

#We need to create an escaped path for sed command
SECRET_P12_ESCAPE="${SECRET_P12//"/"/\/}"

#Retrieve the cubbyhole token from mount, and get the client_token value.
CUBBY_TOKEN=`cat /var/run/secrets/coi/secret.json | jq -c -r '.data.value.auth.client_token'`

# check cubby_token at early stage.
check_null ${CUBBY_TOKEN}
if [ $? -ne 0 ]; then
  echo "Cubbyhole token is empty. Exit."
  exit 1
fi

#Setup Consul Address
export CONSUL_ADDR=${CONSUL_ADDR:-http://localhost:8500}

#Check and wait until Consul service is up.  Once it is up, find out the data center value.  E.g., alln-dev
while [ -z ${CONSUL_DATACENTER} ]; do
    export CONSUL_DATACENTER=`curl --silent ${CONSUL_ADDR}/v1/agent/self | jq -r '.Config.Datacenter'`
    sleep 1s
done
echo "Consul data center is "${CONSUL_DATACENTER}

#Setup Vault service address
export VAULT_ADDR=http://${VAULT_SERVICE:-vault}.service.${CONSUL_DATACENTER}.coi:8200
echo "Vault addr is "${VAULT_ADDR}

#Start IF clause if we don't have the cert yet
if [ ! -e $SECRET_P12 ]; then
     
    #Retrieve the VAULT_TOKEN using the client_token above.  It will call cubbyhole and ask for client_token.  Once we get it, store it in the VAULT_TOKEN variable.
	echo "Getting vault token"
	retry_get ${VAULT_ADDR}/v1/cubbyhole/${VAULT_SERVICE_NAME}/client_token ${CUBBY_TOKEN} '.data.client_token' 20
	export VAULT_TOKEN=${RESP}
    
    
    #Start by creating the directory
    mkdir $SECRET_DIR

    #Retrieve CA CHAIN from VAULT
	echo "Retrieving CA CHAIN"
	retry_get ${VAULT_ADDR}/v1/secret/platform/ca_chain ${VAULT_TOKEN} '.data.value' 20
	echo "$RESP" | base64 -d > ${CA_CHAIN}

    #Retrieve CERT key from VAULT
	echo "Retrieving KEY"
	retry_get ${VAULT_ADDR}/v1/secret/${VAULT_SERVICE_NAME}/${VAULT_SERVICE_NAME}.key ${VAULT_TOKEN} '.data.value' 20
	echo "$RESP" | base64 -d > ${CERT_KEY}

    #Retrieve CSR from VAULT
	echo "Reading CSR"
	retry_get ${VAULT_ADDR}/v1/secret/${VAULT_SERVICE_NAME}/${VAULT_SERVICE_NAME}.csr ${VAULT_TOKEN} '.data.value' 20
	echo "$RESP" | base64 -d > ${CSR_CERT}

    #Escape CSR newline with \\n so that we can send this csr in JSON format later
    SERVICE_CSR=`cat $CSR_CERT | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\\\n/g'`

    #Use openssl to get the CN of the csr
    echo "Get CN"
    CERT_CN=`openssl req -text -in $CSR_CERT | grep Subject: | cut -d "'" -f 2`
  #  echo $CERT_CN

    for i in {1..20}; do
	  echo "Attempting to sign CSR for the ${i} time"
	  RESP_SIGN=`curl --silent -XPOST -H "X-Vault-Token: ${VAULT_TOKEN}" -d '{ "csr": "'"$SERVICE_CSR"'","common_name": "'"${CERT_CN}"'","alt_names": "'"${ALT_NAME}"'","format": "pem"}' ${VAULT_ADDR}/v1/oneid-${CONSUL_DATACENTER}-ca/sign/${VAULT_SERVICE_NAME} | jq -c -r '.data.certificate'`

	  check_null ${RESP_SIGN}
	  if [ $? -eq 0 ]; then
	    echo "$RESP_SIGN" > ${SIGN_CERT}
	    break
	  fi
	  sleep 5
	done
	
    #Append ca chain into our signed cert
    echo "Combine Signed Cert with CA CHAIN"
    cat $CA_CHAIN >> $SIGN_CERT

    #Create pkcs12 format from our signed cert and key.  We use the random password we generated above.
    echo "Create a PKCS12 formatted cert"
    openssl pkcs12 -export -in $SIGN_CERT -inkey $CERT_KEY -out $SECRET_P12 -password pass:$KEYSTORE_PASSWORD -name $VAULT_SERVICE_NAME

    #Remove all cert entries from file
  	rm $CA_CHAIN
  	rm $CERT_KEY
  	rm $CSR_CERT
  	rm $SIGN_CERT

  	#Update permission on p12 file
  	chmod 440 $SECRET_P12

    #Replace application.conf for keystore password and keystore path
     echo "Updating cert password"
     sed -i "s/key-store-password: .*$/key-store-password: "$KEYSTORE_PASSWORD"/" /app/application.yaml
     echo "Updating cert path"
     sed -i "s/key-store: .*$/key-store: "$SECRET_P12_ESCAPE"/" /app/application.yaml

fi

java -server -Xms$JVM_MEMORY -Xmx$JVM_MEMORY -XX:+UseG1GC -XX:ParallelGCThreads=4 -XX:ConcGCThreads=4 -jar /app/boot.jar --spring.config.location=file:/app/application.yaml

echo "$APP_NAME Stopped!"
