#!/bin/sh

GPIO_STRIKE_PIN=17
GPIO_STRIKE_PATH=/sys/class/gpio/gpio$GPIO_STRIKE_PIN

GPIO_DB_OPEN_PIN=27
GPIO_DB_OPEN_PATH=/sys/class/gpio/gpio$GPIO_DB_OPEN_PIN

GPIO_DB_CLOSE_PIN=22
GPIO_DB_CLOSE_PATH=/sys/class/gpio/gpio$GPIO_DB_CLOSE_PIN

cd "`dirname $0`"


init_door() {
	echo $GPIO_STRIKE_PIN > /sys/class/gpio/export
	echo $GPIO_DB_OPEN_PIN > /sys/class/gpio/export
	echo in > $GPIO_DB_OPEN_PATH/direction
	echo $GPIO_DB_CLOSE_PIN > /sys/class/gpio/export
	echo in > $GPIO_DB_CLOSE_PATH/direction
}

unlock_door() {
	echo out > $GPIO_STRIKE_PATH/direction
	echo 0 > $GPIO_STRIKE_PATH/value

	(
		echo out > $GPIO_DB_OPEN_PATH/direction
		echo 1 > $GPIO_DB_OPEN_PATH/value
		sleep 1
		echo in > $GPIO_DB_OPEN_PATH/direction
	) &
}


#logToDB logs Information about Identity contained in the certificte into the database. So one is able to reconstruct who got when Access. 
logToDB() {
	#walk through multilined subject (line by line) and extract Identity-values
	LINE_NR="0"
	if [ -e $CERT_FILE ]; then
		while true
		do	
			LINE_NR=$(($LINE_NR+1))
			#'subject=' means one has reached the first line (the loop is starting at the most bottom line)
			if [ $(printf $(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1)) = 'subject=' 1> /dev/null ]; then break
			else	
				if openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | grep "emailAddress=" 1> /dev/null; then
					EMAIL=$(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | sed 's/\.*emailAddress=//')
				elif openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | grep "commonName=" 1> /dev/null; then
					COMMONNAME=$(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | sed 's/\.*commonName=//') 1> /dev/null
				elif openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | grep "organizationalUnitName=" 1> /dev/null; then
					ORGANIZATIONALUNITNAME=$(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | sed 's/\.*organizationalUnitName=//')
				elif openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | grep "organizationName=" 1> /dev/null; then
					ORGANIZATIONNAME=$(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | sed 's/\.*organizationName=//')
				elif openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | grep "localityName=" 1> /dev/null; then
					LOCALITYNAME=$(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | sed 's/\.*localityName=//')
				elif openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | grep "stateOrProvinceName=" 1> /dev/null; then
					STATEORPROVINCENAME=$(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | sed 's/\.*stateOrProvinceName=//')
				elif openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | grep "countryName=" 1> /dev/null; then
					COUNTRYNAME=$(openssl x509 -in $CERT_FILE -noout -subject -nameopt sep_multiline,lname | tail -$LINE_NR | head -1 | sed 's/\.*countryName=//')
				fi 
			fi
		done
	fi
	
	#look wether Identity tried to get Access somewhere in the past
	IDofExistingIdentity=$(sqlite3 ./logDB.sqlite "Select ID from Identity WHERE email='$EMAIL' AND CommonName='$COMMONNAME' AND OrganizationalUnitName='$ORGANIZATIONALUNITNAME' AND OrganizationName='$ORGANIZATIONNAME' AND LocalityName='$LOCALITYNAME' AND StateOrProvinceName ='$STATEORPROVINCENAME' AND CountryName='$COUNTRYNAME'")
	#if Identity hasn´t tried to get Access in the past, insert it and look up the ID under which it was inserted
	if (test -z $IDofExistingIdentity)
	then sqlite3 ./logDB.sqlite "Insert INTO Identity (email, CommonName, OrganizationalUnitName, OrganizationName, LocalityName, StateOrProvinceName, CountryName) VALUES ('$EMAIL', '$COMMONNAME', '$ORGANIZATIONALUNITNAME', '$ORGANIZATIONNAME', '$LOCALITYNAME', '$STATEORPROVINCENAME', '$COUNTRYNAME');"
	IDofExistingIdentity=$(sqlite3 ./logDB.sqlite "Select ID from Identity WHERE email='$EMAIL' AND CommonName='$COMMONNAME' AND OrganizationalUnitName='$ORGANIZATIONALUNITNAME' AND OrganizationName='$ORGANIZATIONNAME' AND LocalityName='$LOCALITYNAME' AND StateOrProvinceName ='$STATEORPROVINCENAME' AND CountryName='$COUNTRYNAME'")
	fi
	#Actual Logging into database
	sqlite3 ./logDB.sqlite "Insert INTO AccessAttempt (Identity_ID, timestamp, success)  VALUES ('$IDofExistingIdentity', CURRENT_TIMESTAMP, '$1');";
}


lock_door() {
	echo in > $GPIO_STRIKE_PATH/direction
}

access_denied() {
	echo Access Denied: $AUTH_DN

	# TODO: Log the incident.

	# Disable starting beep
	opensc-tool --send-apdu FF:00:52:00:00 > /dev/null 2> /dev/null

	# Beep three times with red LED to indicate failure
	# opensc-tool --send-apdu FF:00:40:5D:04:01:01:03:01 > /dev/null 2> /dev/null
	# opensc-tool --send-apdu FF:00:40:5D:04:01:01:02:01 beep twice
	# sleep 1
}

access_granted() {
	echo Access Granted: $AUTH_DN

	unlock_door

	# Beep once with green LED to indicate success
	opensc-tool --send-apdu FF:00:40:2E:04:01:01:01:01 > /dev/null 2> /dev/null

	# Disable starting beep
	opensc-tool --send-apdu FF:00:52:00:00 > /dev/null 2> /dev/null

	sleep 4

	lock_door
}

verify_access() {
	# TODO: Look up and verify that $AUTH_DN has access to this zone!
	true
}

init_door

echo Starting Auth Loop

# Main access control loop
while true ;
do
	lock_door
	if AUTH_DN=`./simple-card-auth.sh`
	then if verify_access
		then access_granted
		else access_denied
		fi
	else access_denied
	fi
done
