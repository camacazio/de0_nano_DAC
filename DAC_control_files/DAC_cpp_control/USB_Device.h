/*
Header file for defining a class for the USB-controlled FPGA waveform cards
*/
#pragma once

#include <vector> //needed for the vector of devices
#include <map> //needed for the waveform channel map
#include <string> // needed for parsing the device initalization list in fpgart.cpp from a defined list
#include <wtypes.h> //needed for certain variable types in FTD2XX.H
#include "FTD2XX.H" // Header file for USB controls and types

// Parse by white space, listing serial numbers and number of dacs on that serial number
// "Serial# #DACs Serial# #DACs ..."
#define USB_DEVICE_LIST "TESTER00 2"

#define USB_BYTE_RANGE 65535 // max number for positive values: unsigned 16-bit
#define USB_MAX_VOLTAGE 10.0 // max voltage value taken at USB_BYTE_RANGE
#define USB_DAC_UPDATE 0.0005 // all times should be in milliseconds
#define MIN_LINE_TIME 0.002 // in milliseconds, set by the time it takes to read in the starting voltage and duration (4 clock cycles)
#define MAX_LINE_TIME 32.600 // 32.6 milliseconds per waveform line; overhead is reserved to allow higher time values to be "op-codes" in memory

#define MIN_VOLTAGE 0.0
#define MAX_VOLTAGE 10.0

// Some typedef's for the USB data vectors
typedef	std::vector<BYTE> USBWVF_data;
typedef std::map<unsigned, USBWVF_data> USBWVF_channel;
typedef std::map<unsigned, USBWVF_channel> USBWVF;

// This is the definition for the Class used for USB control of the USB-connected FPGA devices
class USB_WaveDev{
  public:
	// default constructor
	USB_WaveDev();

	FT_STATUS Open(); //Opens the device for accessing, sets ftHandle
	FT_STATUS Write(BYTE* wavePoint, DWORD size); //Writes a waveform to the device as a string of bytes
	FT_STATUS Close(); //Closes the device on shutdown

	//serial numbers are 8 characters followed by TWO nulls to give length 10
	char Serial[10]; //serial number of the device is stored here
	unsigned num_DACs; //the number of DACs on this USB device

  private:
	FT_HANDLE ftHandle; //the handle for the device
	DWORD written; //the write command uses this for how much data was sent
};

class USB_Waveform_Manager{
public:
	// Section of functions for accessing USB FT245RL communication commands

	// Ask the USB API to generate a list of FTDI devices
	static FT_STATUS CreateDeviceInfoList(DWORD * numDevs) {return FT_CreateDeviceInfoList(numDevs); };

	// Ask the USB API to retrieve the list of FTDI devices and their information (generated by CreatDeviceInfoList)
	static FT_STATUS GetDeviceInfoList(FT_DEVICE_LIST_INFO_NODE * devInfo, DWORD * numDevs) {return FT_GetDeviceInfoList(devInfo, numDevs); };
	
	// get the index of FTDI device given a serial number (eg 'TESTDEV0')
	static int GetDeviceIndexFromSerialNumber(string * mySerialNo);
	
	// Sizes the device list based on the number of DAC devices found
	static void ListSize(DWORD numDACcontrollers) { USBWaveDevList.resize(numDACcontrollers); };

	// Fills out a vector with an instance of a DAC device and opens it
	static FT_STATUS InitSingleDACMaster(DWORD devIndex, const char * serialNum, unsigned dacNum);

	// Close a device
	static FT_STATUS CloseDevice(DWORD devIndex) {return USBWaveDevList.at(devIndex).Close(); };

	//Section of functions for handling Waveform data

	// Clear out the data in a channel or step, or clear it all
	static void WvfClear(int channel, int step);

	// Defines the device list, but isn't used until after the size is defined
	static std::vector<USB_WaveDev> USBWaveDevList;
	// Defines the waveform data map between a channel number and data to be sent there as a BYTE vector
	static USBWVF USBWvf;

//private:
	// Fill out the data in a waveform as bytes derived from vectors sent from a waveform file
	static bool WvfFill(unsigned channel, unsigned step,
		std::vector<double> vTimeVals, std::vector<double> vCurVals, std::vector<double> vdVVals);

	// Write a channel of data to a device
	static bool WvfWrite(unsigned channel);

	// Run the waveform on the device
	static bool WvfRun(unsigned channel);
};