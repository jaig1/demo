#!/bin/bash 
echo "Starting $APP_NAME"

#Define where to put the certificate
SECRET_DIR=/app/secret
 
#Define where to store the key, csr, signed cert and ca
CERT_KEY=/etc/nginx/ssl/key.key
CSR_CERT=/etc/nginx/ssl/csr.csr
SIGN_CERT=/etc/nginx/ssl/sign_cert.pem
CA_CHAIN=/etc/nginx/ssl/ca_chain.pem
FINISHED_FILE=/etc/nginx/ssl/finished

#Define where to store the pkcs12 keystore
SECRET_P12=$SECRET_DIR/keystore.p12
 
#Generate a random keystore password
#KEYSTORE_PASSWORD= 'TESTPASSWORD'
#$(date | md5sum | base64)
 
#We need to create an escaped path for sed command
SECRET_P12_ESCAPE="${SECRET_P12//"/"/\/}"
 
#Retrieve the cubbyhole token from mount, and get the client_token value.
CUBBY_TOKEN=`cat /var/run/secrets/coi/secret.json | jq -c -r '.data.value.auth.client_token'`

#Setup Consul Address
export CONSUL_ADDR=${CONSUL_ADDR:-http://localhost:8500}
 
#Check and wait until Consul service is up.  Once it is up, find out the data center value.  E.g., alln-dev
while [ -z ${CONSUL_DATACENTER} ]; do
    CONSUL_DATACENTER=`curl --silent ${CONSUL_ADDR}/v1/agent/self | jq -r '.Config.Datacenter'`
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
    if [ -z ${VAULT_TOKEN} ]; then
       export VAULT_TOKEN=`curl --silent -XGET -H 'x-vault-token: '${CUBBY_TOKEN} ${VAULT_ADDR}/v1/cubbyhole/${VAULT_SERVICE_NAME}/client_token | jq -c -r '.data.client_token'`
       if [ -z ${VAULT_TOKEN} ]; then
            echo "Couldn't locate vault token"
            exit 1
       fi
    fi
   # echo "VAULT TOKEN TEST"
  #  echo ${VAULT_TOKEN}
    #Start by creating the directory
    mkdir $SECRET_DIR
     
    #Retrieve CA CHAIN from VAULT
    echo "Retrieving CA CHAIN"
    curl -XGET -H 'x-vault-token: '${VAULT_TOKEN} ${VAULT_ADDR}/v1/secret/platform/ca_chain | jq -c -r '.data.value' | base64 -d > $CA_CHAIN
  #  cat $CA_CHAIN
       
    #Retrieve CERT key from VAULT
    echo "Retrieving KEY"
    curl -XGET -H 'x-vault-token: '${VAULT_TOKEN} ${VAULT_ADDR}/v1/secret/${VAULT_SERVICE_NAME}/${VAULT_SERVICE_NAME}.key | jq -c -r '.data.value' | base64 -d > $CERT_KEY
  #  cat $CERT_KEY
    
    #Retrieve CSR from VAULT
    echo "Reading CSR"
    curl -XGET -H 'x-vault-token: '${VAULT_TOKEN} ${VAULT_ADDR}/v1/secret/${VAULT_SERVICE_NAME}/${VAULT_SERVICE_NAME}.csr | jq -c -r '.data.value' | base64 -d > $CSR_CERT
  #  cat $CSR_CERT
    
    #Escape CSR newline with \\n so that we can send this csr in JSON format later
    SERVICE_CSR=`cat $CSR_CERT | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\\\n/g'`

    #Use openssl to get the CN of the csr
    echo "Get CN"
    CERT_CN=`openssl req -text -in $CSR_CERT | grep Subject: | cut -d "'" -f 2`
  #  echo $CERT_CN

    #Sign CSR.  We pass the CSR value, CN and SAN.  We use the vault token we have to sign the cert.  Return value is in JSON format, so use jq to get value from JSON and store it in file
    echo "Signing CSR"
    curl --silent -XPOST -H "X-Vault-Token: ${VAULT_TOKEN}" -d '{ "csr": "'"$SERVICE_CSR"'","common_name": "'"${CERT_CN}"'","alt_names": "'"${CONSUL_SERVICE_NAME}"'.service.'"${CONSUL_DATACENTER}"'.coi","format": "pem"}' ${VAULT_ADDR}/v1/oneid-${CONSUL_DATACENTER}-ca/sign/${VAULT_SERVICE_NAME} | jq -c -r '.data.certificate' > $SIGN_CERT
     
    #Append ca chain into our signed cert
    echo "Combine Signed Cert with CA CHAIN"
    cat $CA_CHAIN >> $SIGN_CERT
     
    #Create pkcs12 format from our signed cert and key.  We use the random password we generated above.
   # echo "Create a PKCS12 formatted cert"
   # openssl pkcs12 -export -in $SIGN_CERT -inkey $CERT_KEY -out $SECRET_P12 -name $VAULT_SERVICE_NAME
    
    touch $FINISHED_FILE
     
    #Remove all cert entries from file
    rm $CA_CHAIN
   #rm $CERT_KEY
    rm $CSR_CERT
    #rm $SIGN_CERT
     
    #Update permission on p12 file
    #chmod 440 $SECRET_P12
    chmod 440 $CERT_KEY
    chmod 440 $SIGN_CERT

    #Replace application.conf for keystore password and keystore path
    # echo "Updating cert password"
    # sed -i "s/ssl.key-store-password = .*$/ssl.key-store-password : \""$KEYSTORE_PASSWORD"\"/" /app/$APP_NAME_VERSION/conf/application.conf
    #  echo "Updating cert path"
    # sed -i "s/ssl.key-store =.*$/ssl.key-store : "$SECRET_P12_ESCAPE"/" /app/$APP_NAME_VERSION/conf/application.conf
     
fi

java -server -Xmx1024M -jar /app/boot.jar

echo "$APP_NAME Stopped!"