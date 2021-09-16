#!/bin/sh
export OPENSC_CONF=`pwd`/opensc.conf

CACHE_DIR="$PWD/cache"
CHAL_FILE="$CACHE_DIR/chal.tmp"
CHALHASH_FILE="$CACHE_DIR/chalhash.tmp"

CERT_FILE="$CACHE_DIR/cert.pem"
PUB_KEY_FILE="$CACHE_DIR/pub_key.pem"
SIG_FILE="$CACHE_DIR/sig.tmp"
SERIAL_FILE="$CACHE_DIR/serial.tmp"
TMP_FILE="$CACHE_DIR/temporary.tmp"

# Where to look for PIV Certificate.
# Slot 4 is used for pure Authentication
# Inspect with pkcs15-tool --list-certificates
KEY_ID=4
# OpenSSL strict self-signed checking
STRICT_CHECK=1
RAND_FILE=/dev/urandom
STDERR=/dev/null

# Get ATR
#ATR_FILE=ATR.tmp
#opensc-tool -w -a 2> "$STDERR" > "$ATR_FILE"

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
	rm -rf $CACHE_DIR 2> /dev/null
}

die() {
	# Helper function to halt execution if one of our instructions exited unsuccessfully
	grep -v -e "Sending" -e "Receiv" "$SERIAL_FILE" | tail -n 1 2> "$STDERR"

	[ "0$DEBUG" -lt 1 ] && cleanup

	echo died
	exit 1
}



# Main routine - initialize everything
cleanup

mkdir -p $CACHE_DIR
# Calculate a challenge
dd if="$RAND_FILE" of="$CHAL_FILE" bs=32 count=1 2> "$STDERR" || die

# Calculate the hash of the challenge
openssl sha256 -sha256 -binary < "$CHAL_FILE" > "$CHALHASH_FILE" || die

# Wait for card and get CHUID (Card Holder Unique Identifier)
# Standard Yubikey Preamble? 00:a4:04:00:09:a0:00:00:03:08:00:00:10:00
# Read CHUID (Card Holder Unique Identifier) 00:cb:3f:ff:05:5C:03:5f:C1:02
# Read Yubikey S/N 00:f8:00:00
# https://docs.yubico.com/yesdk/users-manual/application-piv/apdu/get-data.html
# https://docs.yubico.com/yesdk/users-manual/application-piv/apdu/metadata.html
opensc-tool -w --send-apdu FFCA000000 --send-apdu 00:a4:04:00:09:a0:00:00:03:08:00:00:10:00 --send-apdu 00:f8:00:00   > $TMP_FILE || die
# cat $SERIAL_FILE | openssl sha1 | cut -d ' ' -f 2 > $SERIAL_FILE

# Yubikey Serial Number to Decimal
grep -v -e "Sending" -e "Receiv" $TMP_FILE | tail -n 1 | grep -Pzo '([A-Z0-9]{2})' | (read hex; echo $(( 0x${hex} ))) > $SERIAL_FILE

# Export Certificate
pkcs15-tool $PKCS15_CRYPT_FLAGS -L --read-certificate "$KEY_ID" -o "$CERT_FILE" > "$STDERR" 2> "$STDERR" || die

# Verify the certificate (no CRL check is made, due to looking up users' activation status in LDAP)
# openssl verify -verbose -x509_strict -crl_check -CAfile ca.crt cert.pem
openssl verify -x509_strict -CAfile ca.crt -verbose -purpose sslclient $CERT_FILE > $TMP_FILE || die

# Calculate the response for the challenge
pkcs15-crypt $PKCS15_CRYPT_FLAGS -s -k $KEY_ID --sha-256 --pkcs1 -i $CHALHASH_FILE -o $SIG_FILE 2> $STDERR || die

# The openssl verify command is very lenient when it comes to
# self-signed certificates. This is an obvious security hole in this
# use case. The following check makes sure that if there is anything
# except perfect verification that we fail.
[ $STRICT_CHECK = 1 ] && [ "`cat $TMP_FILE`" '!=' "$CERT_FILE: OK" ] && die

# Extract the public key
openssl x509 -pubkey -noout -in $CERT_FILE > $PUB_KEY_FILE || die

# Verify the response
openssl dgst -sha256 -verify $PUB_KEY_FILE -signature $SIG_FILE $CHAL_FILE 2>&1 > $STDERR || die

# Save subject CN
openssl x509 -in $CERT_FILE -nameopt RFC2253 -noout -subject | sed 's/subject=//' > $SUBJECT_DN_FILE || die

echo success
exit 0