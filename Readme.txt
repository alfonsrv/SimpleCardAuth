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

sudo pcscd --apdu --foreground --info
sudo pcscd --foreground --error

./uhubctl -a 1 -p 1-4 -l 1-1 -r 2
pidof pcscd | xargs kill -9
Reader Reset https://github.com/mvp/uhubctl

# pcscd
00159237 ccid_usb.c:898:ReadUSB() read failed (1/5): -7 LIBUSB_ERROR_TIMEOUT                                                                                                                                                                                                                                  
00058316 ccid_usb.c:920:ReadUSB() Duplicate frame detected                                                             
00100296 ccid_usb.c:898:ReadUSB() read failed (1/5): -7 LIBUSB_ERROR_TIMEOUT
00000579 readerfactory.c:1106:RFInitializeReader() Open Port 0x200000 Failed (usb:072f/2200:libudev:0:/dev/bus/usb/001/005)
00001099 hotplug_libudev.c:523:HPAddDevice() Failed adding USB device: ACS ACR122U PICC Interface

# STDERR
Waiting for a reader to be attached...
Error while waiting for a reader: No readers found


# pcscd
Card inserted into ACS ACR122U PICC