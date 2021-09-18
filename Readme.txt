In order to install SimpleCardAuth on the RaspberryPi execute the following commands:
## RPI Installation ##

sudo apt-get install libusb-dev libusb++-0.1-4c2
sudo apt-get install libccid

sudo apt-get install pcscd

sudo apt-get install libpcsclite1
sudo apt-get install libpcsclite-dev
sudo apt-get install pcsc-tools
sudo apt-get install libpcsc-perl

sudo modprobe -r pn533
sudo modprobe -r nfc

sudo apt-get install libssl-dev
sudo apt-get install libreadline-dev

sudo apt-get install coolkey pcscd pcsc-tools pkg-config libpam-pkcs11 opensc libengine-pkcs11-openssl libssl1.0-dev

---

Simply install OpenSC

	"mute":[0xFF, 0x00, 0x52, 0x00, 0x00],
	"unmute":[0xFF, 0x00, 0x52, 0xFF, 0x00],
	"getuid":[0xFF, 0xCA, 0x00, 0x00, 0x00],
	"firmver":[0xFF, 0x00, 0x48, 0x00, 0x00],

Reader Reset https://github.com/mvp/uhubctl