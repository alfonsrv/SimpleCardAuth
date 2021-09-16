#!/bin/sh

CHAL_FILE=chal.tmp
CHALHASH_FILE=chalhash.tmp
CERT_FILE=cert.pem
PUB_KEY_FILE=pub_key.pem
SIG_FILE=sig.tmp
SIG2_FILE=sig2.tmp
ATR_FILE=ATR.tmp
SUBJECT_DN_FILE=subject-dn.tmp
SERIAL_FILE=serial.tmp
TMP_FILE=temporary.tmp


STRICT_CHECK=1
# Where to look for PIV Certificate
KEY_ID=1
RAND_FILE=/dev/urandom
STDERR=/dev/null

CACHE_DIR=`pwd`/card-cache
export OPENSC_CONF=`pwd`/opensc.conf

if [ "0$DEBUG" -gt 2 ]
then PKCS15_CRYPT_FLAGS=-vvv
fi

if [ "0$DEBUG" -gt 1 ]
then
	STDERR=/dev/stderr
	set -x
fi

cleanup() {
	# Clean-up temporary files
	rm $CHAL_FILE 2> /dev/null
	rm $CERT_FILE 2> /dev/null
	rm $CHALHASH_FILE 2> /dev/null
	rm $PUB_KEY_FILE 2> /dev/null
	rm $SIG_FILE 2> /dev/null
	rm $SIG2_FILE 2> /dev/null
	rm $ATR_FILE 2> /dev/null
	rm $SERIAL_FILE 2> /dev/null
	rm $TMP_FILE 2> /dev/null
}

cache_cert() {
	cache_file="$CACHE_DIR/`cat $SERIAL_FILE | openssl sha1 | cut -d ' ' -f 2`"
	mkdir -p "$CACHE_DIR"
	cp "$CERT_FILE" "$cache_file"
}

cache_lookup() {
	cache_file="$CACHE_DIR/`cat $SERIAL_FILE | openssl sha1 | cut -d ' ' -f 2`"
	if [ -f "$cache_file" ]
	then
		#echo Cache hit
		cp "$cache_file" "$CERT_FILE"
	else return 1
	fi
}

uncache_cert() {
	cache_file="$CACHE_DIR/`cat $SERIAL_FILE | openssl sha1 | cut -d ' ' -f 2`"
	rm -f "$cache_file"
}


die() {
	grep -v -e "Sending" -e "Receiv" "$SERIAL_FILE" | tail -n 1 2> "$STDERR"
	
	#log the failed AccessAttempt
	#echo logging
	#logToDB 0
	
	[ "0$DEBUG" -lt 1 ] && cleanup

	#AntiBruteforce-Timelock
	#If 3 times within 30 seconds a AuthenticationFailure is recognized, the Authentication will be locked for 30 seconds.
	#For performance reasons the FailureTimestamps.txt is used instead of logDB.sqlite
	#Save NewestFailureTimestamp at the End of the file
	echo $(date +%s) >> FailureTimestamps.txt
	if [ $(wc -l <FailureTimestamps.txt) -ge 3 ]
	#Remove OldestFailureTimestamp if more than 3 Timestamps are saved
	then echo "$(tail -3 FailureTimestamps.txt)" > FailureTimestamps.txt
		if [ $(($(tail -1 FailureTimestamps.txt)-$(head -1 FailureTimestamps.txt))) -lt 30 ] 
			then sleep 30s
		fi
	fi
	echo died
	exit 1
}

cleanup

# Get ATR
#opensc-tool -w -a 2> "$STDERR" > "$ATR_FILE"

# Calculate a challenge
dd if="$RAND_FILE" of="$CHAL_FILE" bs=32 count=1 2> "$STDERR" || die

# Calculate the hash of the challenge
openssl sha256 -sha256 -binary < "$CHAL_FILE" > "$CHALHASH_FILE" || die

# Get Serial
# https://docs.yubico.com/yesdk/users-manual/application-piv/apdu/get-data.html
# https://docs.yubico.com/yesdk/users-manual/application-piv/apdu/metadata.html
# Get Serial Hardware S/N Yubikey 00:f8:00:00
opensc-tool -w --send-apdu FFCA000000 --send-apdu 00:a4:04:00:09:a0:00:00:03:08:00:00:10:00 --send-apdu 00:cb:3f:ff:05:5C:03:5f:C1:02 2> $STDERR > "$SERIAL_FILE" || die
#opensc-tool --serial --send-apdu FFCA000000 2> $STDERR > "$SERIAL_FILE" || die

# See if the card is in the cache, and if so load it up.
#cache_lookup || {
	# Extract the certificate
#	pkcs15-tool $PKCS15_CRYPT_FLAGS -L --read-certificate "$KEY_ID" -o "$CERT_FILE" > "$STDERR" 2> "$STDERR" || die
#}

# Export Certificate
pkcs15-tool $PKCS15_CRYPT_FLAGS -L --read-certificate "$KEY_ID" -o "$CERT_FILE"

# Calculate the response for the challenge
if ( openssl x509 -in cert.pem -text | grep -q -s "Public Key Algorithm: id-ecPublicKey" ) ;
then
	# ECDSA signatures need to be converted to DER format.
	pkcs15-crypt $PKCS15_CRYPT_FLAGS -s -k $KEY_ID --sha-256 -i $CHALHASH_FILE -o $SIG2_FILE 2> $STDERR || die
	./ecdsa-pkcs11-to-asn1 < $SIG2_FILE > $SIG_FILE || die
else
	pkcs15-crypt $PKCS15_CRYPT_FLAGS -s -k $KEY_ID --sha-256 --pkcs1 -i $CHALHASH_FILE -o $SIG_FILE 2> $STDERR || die
fi

# Verify the certificate
cat $CERT_FILE | openssl verify -crl_check -CAfile ca.crt -verbose -purpose sslclient > $TMP_FILE || {
	uncache_cert
	die
}

# The openssl verify command is very lenient when it comes to
# self-signed certificates. This is an obvious security hole in this
# use case. The following check makes sure that if there is anything
# except perfect verification that we fail.
[ $STRICT_CHECK = 1 ] && [ "`cat $TMP_FILE`" '!=' "stdin: OK" ] && die

# Extract the public key
openssl x509 -pubkey -noout -in $CERT_FILE > $PUB_KEY_FILE || die

# Verify the response
openssl dgst -sha256 -verify $PUB_KEY_FILE -signature $SIG_FILE $CHAL_FILE 2>&1 > $STDERR || die

# Print out the subject name
openssl x509 -in $CERT_FILE -nameopt RFC2253 -noout -subject | sed 's:^[^ ]* ::' |  tee $SUBJECT_DN_FILE || die

#log the successfull AccessAttempt
logToDB 1

# Authentification was successful, so cache the cert so we don't have to read it again.
cache_cert

cleanup
echo successfull
exit 0
