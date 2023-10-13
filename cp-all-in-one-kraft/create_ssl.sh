#!/bin/bash

hst_dns="AZRWEU008706.azure.global.corp.sap"

set -eou pipefail \
    -o errexit

printf "Deleting previous (if any)..."
rm -rf secrets
mkdir secrets
mkdir -p tmp
echo " OK!"
# Generate CA key
printf "Creating CA..."
openssl req -new -x509 -keyout tmp/datahub-ca.key -out tmp/datahub-ca.crt -days 365 -subj '/CN=AZRWEU008706.azure.global.corp.sap:9093/OU=test/O=datahub/L=paris/C=fr' -passin pass:datahub -passout pass:datahub >/dev/null 2>&1
cp tmp/datahub-ca.crt secrets/datahub-ca.crt
echo " OK!"

for i in 'broker' 'producer' 'consumer' 'schema-registry'
do
	printf "Creating cert and keystore of $i..."
	# Create keystores
	keytool -genkey -noprompt \
				 -alias $i \
				 -dname "CN=$i, OU=test, O=datahub, L=paris, C=fr" \
				 -keystore secrets/$i.keystore.jks \
				 -keyalg RSA \
				 -storepass datahub \
				 -keypass datahub  >/dev/null 2>&1

	# Create CSR, sign the key and import back into keystore
	keytool -keystore secrets/$i.keystore.jks -alias $i -certreq -file tmp/$i.csr -storepass datahub -keypass datahub >/dev/null 2>&1

	rm exts.ext || true
	echo "subjectAltName = DNS:$hst_dns, DNS:localhost" > exts.ext
	openssl x509 -req -CA tmp/datahub-ca.crt -CAkey tmp/datahub-ca.key -in tmp/$i.csr -out tmp/$i-ca-signed.crt -days 365 -CAcreateserial -passin pass:datahub \
	  -extfile exts.ext >/dev/null 2>&1

	keytool -keystore secrets/$i.keystore.jks -alias CARoot -import -noprompt -file tmp/datahub-ca.crt -storepass datahub -keypass datahub >/dev/null 2>&1

	keytool -keystore secrets/$i.keystore.jks -alias $i -import -file tmp/$i-ca-signed.crt -storepass datahub -keypass datahub >/dev/null 2>&1

	# Create truststore and import the CA cert.
	keytool -keystore secrets/$i.truststore.jks -alias CARoot -import -noprompt -file tmp/datahub-ca.crt -storepass datahub -keypass datahub >/dev/null 2>&1
  echo " OK!"
done

echo "datahub" > secrets/cert_creds
rm -rf tmp

echo "SUCCEEDED"