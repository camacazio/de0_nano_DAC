// File for definitions such as names for devices, logic, or DAC channels

// Parse by white space, listing serial numbers and number of dacs on that serial number
// "Serial# #Chans Serial# #Chans ..."
#define USB_DEVICE_LIST "DACBRD00 3 DACBRD01 3 DACBRD02 3 DACBRD03 3"

// Devices
#define	DEV0	0
#define DEV1	1
#define DEV2	2
#define DEV3	3

// DAC channels, names for channels to go with devices
#define DAC0	0
#define DAC1	1
#define LOGIC	2

// Chooses whether or not the DAC is configured to loop first waveform in memory
#define	FREERUN	FALSE