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

CACHE_DIR=`pwd`/card-cache

STRICT_CHECK=0
KEY_ID=4
STDERR=/dev/null
#STDERR=/dev/stderr

export OPENSC_CONF=`pwd`/opensc.conf

cleanup() {
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

die() {
#	echo ""
#	echo "ACCESS DENIED."
	cleanup
	exit 1
}

#set -x


# Get ATR
opensc-tool -w -a 2> $STDERR > $ATR_FILE || die

# Get Serial
opensc-tool --serial 2> $STDERR > $SERIAL_FILE || die

# Extract the certificate
( cache_lookup || pkcs15-tool --no-prompt --read-certificate $KEY_ID -o $CERT_FILE 2> $STDERR ) || die

# Verify the certificate
cat $CERT_FILE | openssl verify -CAfile ca.crt -verbose -purpose sslclient > $TMP_FILE || die

[ $STRICT_CHECK = 1 ] && [ "`cat $TMP_FILE`" '!=' "stdin: OK" ] && die


# Extract the public key
openssl x509 -pubkey -noout -in $CERT_FILE > $PUB_KEY_FILE || die

# Calculate a challenge
dd if=/dev/random of=$CHAL_FILE bs=32 count=1 2> $STDERR || die

# Calculate the hash of the challenge
openssl sha -sha256 -binary < $CHAL_FILE > $CHALHASH_FILE || die

# Calculate the response for the challenge
if ( openssl x509 -in cert.pem -text | grep -q -s "Signature Algorithm: ecdsa" ) ;
then
	# ECDSA signatures need to be converted to DER format.
	pkcs15-crypt -s -k $KEY_ID --sha-256 -i $CHALHASH_FILE -o $SIG2_FILE 2> $STDERR || die
	./ecdsa-pkcs11-to-asn1 < $SIG2_FILE > $SIG_FILE || die
else
	pkcs15-crypt -s -k $KEY_ID --sha-256 --pkcs1 -i $CHALHASH_FILE -o $SIG_FILE 2> $STDERR || die
fi

# Verify the response
openssl dgst -sha256 -verify $PUB_KEY_FILE -signature $SIG_FILE $CHAL_FILE 2>&1 > $STDERR || die

# Print out the subject name
openssl x509 -in $CERT_FILE -nameopt RFC2253 -noout -subject | sed 's:^[^ ]* ::' |  tee $SUBJECT_DN_FILE || die

cache_cert

#echo ""
#echo "ACCESS GRANTED."
cleanup
exit 0
