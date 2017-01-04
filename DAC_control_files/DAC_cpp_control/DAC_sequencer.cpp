// usb_test.cpp : Defines the entry point for the console application.
#include "stdafx.h"
using namespace std;

///////////////////////////////////////////////////
//some USB interface code
// Skip to the bottom of this for the main() function that runs this code
///////////////////////////////////////////////////
// Definitions for communication with the DAC device over USB
#include "USB_Device.h"
#include "properties.h"

//Ignore some standard warnings
//#pragma warning(disable:4146)

// global vectors used to hold data as needed for waveform definitions
// waveform data vectors
vector<double> vTime;
vector<double> vVals;
vector<double> vdV;

// The vector of class instances of USB-connected DAC devices
std::vector<USB_WaveDev> USB_Waveform_Manager::USBWaveDevList;
// Holds the channel map of data to be sent to each device
USBWVF USB_Waveform_Manager::USBWvf;

// Definitions for class functions for a USB-connected FPGA card
USB_WaveDev::USB_WaveDev() {}
FT_STATUS USB_WaveDev::Open()
{
	// The device is opened by it's serial number and referenced by it's handle
	return FT_OpenEx(Serial, FT_OPEN_BY_SERIAL_NUMBER, &ftHandle);
}
FT_STATUS USB_WaveDev::Write(BYTE* wavePoint, DWORD size)
{
	// Write can be used to write a waveform or to send a reset command, etc
	//std::cout << "USB::WaveDev::Write() started" << std::endl;
	return FT_Write(ftHandle, wavePoint, size, &written);
}
FT_STATUS USB_WaveDev::Close()
{
    // Finished with the device, so closing it
	return FT_Close(ftHandle);
}

// Definitions for the class functions that are longer than one or two lines for the USB waveform manager
// Sets up a USB waveform device list
FT_STATUS USB_Waveform_Manager::InitSingleDACMaster(DWORD devIndex, const char * serialNum, unsigned dacNum) {
	// Sets the serial number and number of DACs to a class instance
	strncpy_s(USBWaveDevList[devIndex].Serial,serialNum,10);
	USBWaveDevList[devIndex].num_DACs = dacNum;

	// NULL terminate the last two entries of the serial number, just in case
	USBWaveDevList[devIndex].Serial[8] = USBWaveDevList[devIndex].Serial[9] = '\0';

	// Opens the device for accessing
	return USBWaveDevList.at(devIndex).Open();
}

// Maps a serial number to a device index found after scanning USB ports for all FT245RL chips
int USB_Waveform_Manager::GetDeviceIndexFromSerialNumber(string * mySerialNo) {
	// Holds device number and device information
	DWORD numDevs;
	FT_DEVICE_LIST_INFO_NODE* devInfo;

	if (CreateDeviceInfoList(&numDevs) != FT_OK) {return -123404;}
	
	if (numDevs > 0) {
		// allocate storage for list based on numDevs 
		devInfo = (FT_DEVICE_LIST_INFO_NODE*)malloc(sizeof(FT_DEVICE_LIST_INFO_NODE)*numDevs);
		if (GetDeviceInfoList(devInfo, &numDevs) != FT_OK) {return -123405;}
		
		// search for the requested device
		for (unsigned i = 0; i < numDevs; i++) { 
			string foundSerialNo (devInfo[i].SerialNumber);
			if(mySerialNo->compare(foundSerialNo) == 0) {
				return i;
			}
		}
	}
	else { 
		return -123406;
	} //end of if(numDevs>0)

	return 0;
}

// Fill out the data in a waveform as bytes derived from vectors sent from a data file

/*	1) check to make sure the channel and step is there to store data
	2) convert the voltage and time values into pure numbers that are in the range for the DACs
	3) convert to a bit stream
	4) write to a vector, little endian in words (the FPGA's VHDL code expects a lower word followed by a higher word)*/
// DAC channels are always the 1st and 2nd channel on a board
bool USB_Waveform_Manager::WvfFill(unsigned channel, unsigned step,
	std::vector<double> vTimeVals, std::vector<double> vCurVals, std::vector<double> vdVVals)
{
	// Indeces and temporary variables for writing to USBWVF data
	unsigned i = 0;
	unsigned j = 0;
	unsigned __int64 ui;
	__int64 nSteps;
	BYTE uc;

	// Times from a waveform file are in absolute time for when a waveform section ends
	// This is for holding the previous time value; the PDQ wants time durations
	double currentTime;
	double timeInterval;
	double lastTime = 0;

	// Check that the channel has been defined in the waveform list
	USBWVF::iterator itc = USBWvf.find(channel);
	if (itc == USBWvf.end()) {
		// channel isn't defined, so create it
		USBWvf[channel] = USBWVF_channel();
	}
	// Check that the step has been defined in the waveform list
	USBWVF_channel::iterator its = USBWvf[channel].find(step);
	if (its == USBWvf[channel].end()) {
		// step isn't defined, so create it
		USBWvf[channel][step] = USBWVF_data();
	}

	// Used for quick accessing of the channel and step at hand
	USBWVF_data & wvfchanstep = USBWvf[channel][step];

	for (i = 0; i < vCurVals.size(); i++) {

		// Time differences are divided by the DAC update time to get a number of cycles
		currentTime = vTimeVals[i];
		//clamp time intervals
		timeInterval = currentTime - lastTime;
		if (timeInterval < MIN_LINE_TIME) { timeInterval = MIN_LINE_TIME; }
		if (timeInterval > MAX_LINE_TIME) { timeInterval = MAX_LINE_TIME; }
		nSteps = ui = unsigned __int64(ceil(timeInterval / USB_DAC_UPDATE));
		for (j = 0; j < 2; j++) {
			// the data is broken into 2 words and put on the waveform step little endian
			uc = BYTE(ui);
			wvfchanstep.push_back(uc);
			ui = ui >> 8;
		}
		lastTime = currentTime;

		// Check to make sure that vCurVals[i] is in range
		if (vCurVals[i] < MIN_VOLTAGE) {
			vCurVals[i] = MIN_VOLTAGE;
		}
		if (vCurVals[i] > MAX_VOLTAGE) {
			vCurVals[i] = MAX_VOLTAGE;
		}
		// Convert 0V to 10V to a value for full range over a 16 bit number for the FPGA
		ui = unsigned __int64(ceil((vCurVals[i] * USB_BYTE_RANGE) / USB_MAX_VOLTAGE)); //unsigned __int64 is chosen to be certain we have enough data size, fixed, for any machine
		for (j = 0; j < 2; j++) {
			// the data is broken into 2 words and put on the waveform step little endian
			uc = BYTE(ui);
			wvfchanstep.push_back(uc);
			ui = ui >> 8;
		}

		// Check to make sure that vdVVals[i] is in range
		if (vdVVals[i] < MIN_VOLTAGE) {
			vdVVals[i] = MIN_VOLTAGE;
		}
		if (vdVVals[i] > MAX_VOLTAGE) {
			vdVVals[i] = MAX_VOLTAGE;
		}
		// linear coefficient is divided by the total time in number of steps, shifted up to 32 bits to include fractional part	
		ui = unsigned __int64(ceil((USB_BYTE_RANGE + 1)*((vdVVals[i] - vCurVals[i])*USB_BYTE_RANGE) / (nSteps*USB_MAX_VOLTAGE)));
		for (j = 0; j < 4; j++) {
			// the integer part is broken into 4 words and put on the waveform step little endian
			uc = BYTE(ui);
			wvfchanstep.push_back(uc);
			ui = ui >> 8;
		}
	}

	// If in FREERUN, signify end of the step to FPGA with the op-code to loop back to the start of the waveform
	if (FREERUN == TRUE)
	{
		ui = unsigned __int64(USB_BYTE_RANGE - 2);
		for (j = 0; j < 2; j++) {
			// the data is broken into 2 words and put on the waveform step little endian
			uc = BYTE(ui);
			wvfchanstep.push_back(uc);
			ui = ui >> 8;
		}
	}

	// Signify end of the step to FPGA with the op-code to wait for the trigger instead of the next time value
	ui = unsigned __int64(USB_BYTE_RANGE - 1);
	for (j = 0; j < 2; j++) {
		// the data is broken into 2 words and put on the waveform step little endian
		uc = BYTE(ui);
		wvfchanstep.push_back(uc);
		ui = ui >> 8;
	}

	return true;
}

// Fill out the logic data as bytes derived from vectors sent from a data file

/*	1) check to make sure the channel and step is there to store data
	2) convert the logic and time values into pure numbers
	3) convert to a bit stream
	4) write to a vector, little endian in words (the FPGA's VHDL code expects a lower word followed by a higher word)*/
// Logic channels are always the 3rd on a board
bool USB_Waveform_Manager::LogicFill(unsigned channel, unsigned step,
	std::vector<double> vTimeVals, std::vector<double> vLogicVals)
{
	// Indeces and temporary variables for writing to USBWVF data
	unsigned i = 0;
	unsigned j = 0;
	unsigned __int64 ui; // data for byte list
	__int64 nSteps;
	BYTE uc;

	// Times from a waveform file are in absolute time for when a logic section ends
	double timeInterval;

	// Check that the channel has been defined in the waveform list
	USBWVF::iterator itc = USBWvf.find(channel);
	if (itc == USBWvf.end()) {
		// channel isn't defined, so create it
		USBWvf[channel] = USBWVF_channel();
	}
	// Check that the step has been defined in the waveform list
	USBWVF_channel::iterator its = USBWvf[channel].find(step);
	if (its == USBWvf[channel].end()) {
		// step isn't defined, so create it
		USBWvf[channel][step] = USBWVF_data();
	}

	// Used for quick accessing of the channel and step at hand
	USBWVF_data & wvfchanstep = USBWvf[channel][step];

	for (i = 0; i < vLogicVals.size(); i++) {

		// Push logic vector first
		ui = unsigned __int64(vLogicVals[i]); //unsigned __int64 is chosen to be certain we have enough data size, fixed, for any machine
		uc = BYTE(ui);
		wvfchanstep.push_back(uc);

		// Time differences are divided by the DAC update time to get a number of cycles
		timeInterval = vTimeVals[i];
		if (timeInterval < MIN_LOGIC_TIME) { timeInterval = MIN_LOGIC_TIME; }
		if (timeInterval > MAX_LOGIC_TIME) { timeInterval = MAX_LOGIC_TIME; }
		nSteps = ui = unsigned __int64(ceil(timeInterval / LOG_UPDATE));
		for (j = 0; j < 3; j++) {
			// the data is broken into 3 words and put on the waveform step little endian
			uc = BYTE(ui);
			wvfchanstep.push_back(uc);
			ui = ui >> 8;
		}
	}

	// Signify end of the step to FPGA with the op-code to wait for the next trigger instead of the next time value
	ui = unsigned __int64(USB_BYTE_RANGE - 1);
	for (j = 0; j < 2; j++) {
		// the data is broken into 2 words and put on the waveform step little endian
		uc = BYTE(ui);
		wvfchanstep.push_back(uc);
		ui = ui >> 8;
	}

	return true;
}

// Writes all the waveform steps in a channel to the FPGA

/*
1) send data channel
2) send reg_length
3) send burst length
4) write waveform
*/

bool USB_Waveform_Manager::Write(unsigned channel) {
	if(!(USBWvf[channel].empty())) {

		// Indeces for writing to USBWVF data
		unsigned j;
		unsigned local_chan;
		unsigned devIndex = 0;	// The first USB device
		unsigned dataLength = 0; // For setting burst/reg_length
		unsigned __int64 ui; BYTE uc; // Used to convert numbers into little endian hex to send into initWave

		BYTE initWave[9]; // Holds the initialization code for the waveform
			// initWave is hard-coded to just the right length
		BYTE * pInit; // Used for walking through the initWave array
		pInit = initWave; // point to the first element of initWave

		BYTE endWave[3]; // Holds the ending code for the last waveform point in memory
		BYTE * pEnd; // Used for walking through the array
		pEnd = endWave; // point to the first element

		vector<BYTE>::pointer waveform_data; //used for the data in each waveform step when transmitting to the PDQ

		// Format the channel to follow the device list across DACs
		local_chan = channel; j = 0;
		// Check which device we must access, returns an error if there are no devices here
		while(local_chan >= USB_Waveform_Manager::USBWaveDevList[devIndex].num_DACs)
		{
			local_chan = local_chan - USB_Waveform_Manager::USBWaveDevList[devIndex].num_DACs;
			devIndex++;
		}

		// Sending the channel number
		*pInit = 0x04;
		pInit++;
		// process channel
		ui = unsigned __int64(local_chan);
		uc = BYTE(ui);
		*pInit = uc;
		pInit++;

		// Memory address to write is to be set to 00 00, at the start of memory
		*pInit = 0x03;
		pInit++;
		*pInit = 0x00;
		pInit++;
		*pInit = 0x00;
		pInit++;

		// The total length of the data is obtained for the channel specified
		for(USBWVF_channel::iterator its = USBWvf[channel].begin(); its != USBWvf[channel].end(); ++its) {
			// If the step isn't empty then procede
			if(!(its->second).empty()) {
				for(j = 0; j < (its->second).size(); ++j) {
					// There is data, put it into dataLength; this counts number of words, 2 bytes is 1 burst
					dataLength++;
				}
			}
		}

		// Set burst length
		*pInit = 0x00;
		// Put the data length as number of words into burst_length
		ui = unsigned __int64(dataLength/2);
		for(j = 0; j < 2; j++) {
			// the data is broken into 2 words and put on the waveform step little endian
			uc = BYTE(ui);
			pInit++;
			*pInit = uc;
			ui = ui>>8;
		}

		// Initiate burst write command
		pInit++;
		*pInit = 0x02;

		// Write the initialization waveform part to the device
		std::cout << "Write the initialization waveform part to the device (USbWaveDevList[].Write)" << std::endl;
		if(USBWaveDevList.size()){
			if (USB_Waveform_Manager::USBWaveDevList[devIndex].Write(&initWave[0], (DWORD) sizeof(initWave)) == FT_OK) {
				// No errors detected
			}
			else {
				// failure
				return false;
			}
		}
		
		// For the channel specified, the data in the channel is sent to the FPGA
		// Send one BYTE at a time, and loop through the BYTE vector in a step for each step in a channel
		// Iterate across the channel, writing in all the steps of the waveform
		std::cout << "Sending the data in the channel to the FPGA (USbWaveDevList[].Write)" << std::endl;
		if(USBWaveDevList.size()){
			for(USBWVF_channel::iterator its = USBWvf[channel].begin(); its != USBWvf[channel].end(); ++its) {
				if(!(its->second).empty()) {
					// Write all the data held in the current step to a specified device
					waveform_data = &(its->second)[0];
					if (USB_Waveform_Manager::USBWaveDevList[devIndex].Write(&waveform_data[0], (DWORD) (its->second).size()) == FT_OK) {
						// No errors detected
					}
					else {
						// failure
						return false;
					}
				}
				// At the end of the step, the final time value should be negative: VHDL code sees this as a pause
			}
		}

		// Send write command to make the final place in memory the "end of memory" op-code
		*pEnd = 0x01;
		pEnd++;
		*pEnd = 0xFF;
		pEnd++;
		*pEnd = 0xFF;

		if (USBWaveDevList.size()){
			if (USB_Waveform_Manager::USBWaveDevList[devIndex].Write(&endWave[0], (DWORD) sizeof(endWave)) == FT_OK) {
				// No errors detected
			}
			else {
				// failure
				return false;
			}
		}

	}
	std::cout << "Returning from USB_Waveform_Manager::WvfWrite with 'true'" << std::endl;
	return true;
}

// Selects a channel and sends the command to trigger a waveform
bool USB_Waveform_Manager::Run(unsigned channel) {

	// Indeces for writing to USBWVF data
	unsigned j;
	unsigned local_chan;
	unsigned devIndex = 0;	// The first USB device
	unsigned __int64 ui; BYTE uc; // Used to convert numbers into little endian hex to send into initWave

	BYTE runWave[3]; // Holds the initialization code for the waveform
	// initWave is hard-coded to just the right length
	BYTE * pInit; // Used for walking through the initWave array
	pInit = runWave; // point to the first element of initWave

	// Format the channel to follow the device list across DACs
	local_chan = channel; j = 0;
	// Check which device we must access, returns an error if there are no devices here
	while (local_chan >= USB_Waveform_Manager::USBWaveDevList[devIndex].num_DACs)
	{
		local_chan = local_chan - USB_Waveform_Manager::USBWaveDevList[devIndex].num_DACs;
		devIndex++;
	}

	// Sending the channel number
	*pInit = 0x04;
	pInit++;
	// process channel
	ui = unsigned __int64(local_chan);
	uc = BYTE(ui);
	*pInit = uc;
	pInit++;

	// Sending the run command
	*pInit = 0x05;

	if (USBWaveDevList.size()){
		if (USB_Waveform_Manager::USBWaveDevList[devIndex].Write(&runWave[0], (DWORD) sizeof(runWave)) == FT_OK) {
			// No errors detected
		}
		else {
			// failure
			return false;
		}
	}
	std::cout << "Returning from USB_Waveform_Manager::WvfRun with 'true'" << std::endl;
	return true;
}

// Clear out the data in a channel or step, or clear it all
void USB_Waveform_Manager::WvfClear(int channel, int step) {
	// Check that the channel has been defined in the waveform list
	USBWVF::iterator itc = USBWvf.find(channel);
	if (channel == -1) {
			// clear all channels
			USBWvf.clear();
	}
	else if (channel < -1 || step < -1) {
		// Bad channel or step choice
	}
	else if (itc == USBWvf.end()) {
		// Channel isn't defined
	}
	else {
		if (step == -1) {
			// remove the channel data
			USBWvf.erase(itc);
		}
		else {
			// Check that the step has been defined in the waveform list
			USBWVF_channel::iterator its = USBWvf[channel].find(step);
			if (its == USBWvf[channel].end()) {
				// step isn't defined
			}
			else{
				// remove the specific step from the waveform
				USBWvf[channel].erase(its);
			}
		}
	}
}
//////////////////////////////////////////
//end of stuff for USB class type functions
//////////////////////////////////////////

// main!
int main()
{
	// -------------------------------

	unsigned tempDevIndex; // local temporary device index when searching through all connected USB devices
	string str(USB_DEVICE_LIST);
    string buf; // Have a buffer string
    stringstream ss(str); // Insert the string into a stream
    vector<string> serialList; // Create vector to hold expected serial numbers for DAC connections
	vector<int> devIndexList; // Create vector to hold expected USB FT245RL device index
	vector<string> dacList; // Create a vector, each master has some number of DAC channels

	// properly parse the USB_WAVEFORM_LIST in USB_Device.h
	// USB waveform card definition: "serial# #ofDACs serial# #ofDACs ..."
	bool i = 0;
	while (ss >> buf) {
		switch (i){
			case 0:
				// Seek out the desired serial number
				tempDevIndex = USB_Waveform_Manager::GetDeviceIndexFromSerialNumber( &buf );
				if (tempDevIndex < 0){
					return -123402;
				}
				devIndexList.push_back(tempDevIndex);
				serialList.push_back(buf); //stores a serial number
				i = 1;
				break;
			case 1:
				dacList.push_back(buf); //stores a number of DACs
				i = 0;
		}
	}

	// This sets the serial numbers and number of DACs of the devices and opens them for accessing
	const char * serialNum;
	unsigned dacNum;
	unsigned numDevs = 0;
	unsigned DACtotal = unsigned(devIndexList.size());
	// Size the vector of devices to match the number of attached devices
	USB_Waveform_Manager::ListSize(DACtotal);
	if (DACtotal > 0) { //numDevs >= len(serialList)

		for(unsigned i = 0; i < DACtotal; i++) {
			serialNum = serialList[i].c_str();
			stringstream ss(dacList[i]); 
			ss >> dacNum;
			if (USB_Waveform_Manager::InitSingleDACMaster(i/*devIndexList.at(i)*/, serialNum, dacNum) == FT_OK) {
				// No errors detected
				std::cout << "Connected to device " << serialNum << endl;
				numDevs++;
			}
			else {
				// failure
				std::cout << "Did not find device " << serialNum << endl;

			}
		}
	}

	// -------------------------------

	// Flags for loops
	bool running = TRUE;
	bool loading = FALSE;
	// Flags for operation
	bool write = FALSE;
	bool run_wvf = FALSE;
	// Information for waveform storage
	unsigned device = 0;
	unsigned channel = 0;
	unsigned step = 0;
	// input for function selection
	char mychar;
	// info for reading a waveform or logic vector from file
	std::string waveformfile = std::string("");

	// Welcome
	std::cout << "\nThis is the DAC control console" << std::endl;

	while (running) {

		vTime.clear();
		vVals.clear();
		vdV.clear();
		step = 0;
		// Here, one can set some options for the desired channel and step for the waveform
		std::cout << "\nCurrent device: " << device << std::endl;
		std::cout << "Current channel: " << channel << std::endl;
		std::cout << "\n<d>evice select\n<c>hannel select\n<l>ogic step\n<s>et constant voltage\n<w>aveform from files\n<r>un next sequence in channel\n\n<q>uit\t\t\t>> ";
		std::cin >> mychar;

		switch (mychar)
		{
		case 'd':
			// Set device
			std::cout << "Available devices 0 to " << numDevs - 1 << std::endl;
			std::cout << "Enter device number: ";
			std::cin >> device;
			break;

		case 'c':
			// Set channel
			std::cout << "0 or 1 correspond to DAC 0 or 1, 2 corresponds to Logic\nEnter channel number: ";
			std::cin >> channel;
			break;

		case 'l':
			loading = TRUE;
			while (loading == TRUE) {
				// in same folder as executable, include extension
				std::cout << "File should be in format of:\ntime_from_start i d1 d0 l3 l2 l1 l0\n with logic line symbols present for desired logic TRUE" << endl;
				std::cout << "Enter local filename (including file type extension):" << std::endl;
				std::cin >> waveformfile;

				// call up the function to load a logic sequence
				if(Logicstep(waveformfile, device, step))
				{
					// increment to next step for next file load
					step++;
					std::cout << "Load more logic steps from file? <y> yes, <n> no: ";
					std::cin >> mychar;
					switch (mychar)
					{
					case 'y': loading = TRUE;
						break;
					case 'n': loading = FALSE;
						break;
					default:
						std::cout << "\nInvalid Selection\n";
						loading = FALSE;
					}
				}
				else
				{
					loading = FALSE;
				}
			}
			// flag the need to write the data
			write = TRUE;
			break;

		case 's':
			// set a contant voltage
			double voltage;
			std::cout << "Set Voltage (0 to 10): ";
			std::cin >> voltage;

			vTime.push_back(0);
			vVals.push_back(voltage);
			vdV.push_back(voltage);

			// Store the data for transmit
			std::cout << "\nFill Waveform ( calling USB_Waveform_Manager::WvfFill(...) )" << std::endl;
			USB_Waveform_Manager::WvfFill(channel + 3 * device, step, vTime, vVals, vdV);

			// flag the need to write the data
			write = TRUE;
			// flag running the next waveform
			run_wvf = TRUE;
			break;

		case 'w':
			loading = TRUE;
			while (loading == TRUE) {
				// in same folder as executable, include extension
				std::cout << "File should be in format of:\ntime_from_start start_voltage end_voltage" << endl;
				std::cout << "Enter local filename (including file type extension):" << std::endl;
				std::cin >> waveformfile;

				// Process the waveform file
				if (Waveform(waveformfile, device, channel, step))
				{
					// Flag whether or not we are done
					if (FREERUN == FALSE)
					{
						// Increment step for next file
						step++;
						std::cout << "Load more waveform steps from file? <y> yes, <n> no: ";
						std::cin >> mychar;
						switch (mychar)
						{
						case 'y': loading = TRUE;
							break;
						case 'n': loading = FALSE;
							break;
						default:
							std::cout << "\nInvalid Selection\n";
							loading = FALSE;
						}
					}
					else
					{
						loading = FALSE;
					}
				}
				else
				{
					loading = FALSE;
				}
			}
			// flag the need to write the data
			write = TRUE;
			break;

		case 'r':
			// flag running the next waveform
			run_wvf = TRUE;
			break;

		case 'q':
			// Quit the program and proceed to closing the USB connection
			running = FALSE;
			break;

		default:
			std::cout << "\nInvalid Selection\n";
		}

		if (write) {
			// Transmit waveform data
			std::cout << "Transmit waveform data ( calling USB_Waveform_Manager::WvfWrite(...) )" << std::endl;
			USB_Waveform_Manager::Write(channel);
			// clear the flag
			write = FALSE;
		}

		if (run_wvf) {
			// send the code to run the waveform on the chosen channel
			Run(device, channel);
			run_wvf = FALSE;
		}

		// clear command, empties all local waveform data
		USB_Waveform_Manager::WvfClear(-1, -1);
	}

	// -------------------------------

	std::cout << "Close devices" << std::endl;
    // Close each device found
	if (DACtotal > 0) {
		for (unsigned i = 0; i < DACtotal; i++) {
			if (USB_Waveform_Manager::CloseDevice(i) == FT_OK) {
				std::cout << "No errors detected. Exit" << std::endl;
				// No errors detected
			}
			else {
				std::cout << "Error closing DAC controller" << std::endl;
				return -123401;
			}
		}
	}
	return 0;
}

bool Logicstep(std::string waveformfile, unsigned devnum, unsigned step)
{
	// logic channel, given as '2' for each device
	unsigned logchan = 2 + 3 * devnum;

	// logic step values
	double duration;
	double logic_val;

	if (waveformfile != "") // check whether file name is valid
	{
		std::cout << "Reading waveform from " << waveformfile << "\n" << std::endl;
		std::string line;
		string buf;
		ifstream wfstream(waveformfile);
		std::stringstream sss;

		if (wfstream.is_open()) // put into loop to read data
		{
			while (getline(wfstream, line))
			{
				std::cout << line << std::endl;
				sss << line;

				// First item in line should be a duration
				sss >> duration;
				// If there is NAN, this means to go to the next step instead
				if (duration == -1) {
					// do nothing
				}
				else {
					vTime.push_back(duration);
					logic_val = 0;
					// Step through the rest of the line
					while (sss >> buf) {
						if (buf == "i") {
							logic_val += pow(2, 6);
						}
						else if (buf == "d1") {
							logic_val += pow(2, 5);
						}
						else if (buf == "d0") {
							logic_val += pow(2, 4);
						}
						else if (buf == "l3") {
							logic_val += pow(2, 3);
						}
						else if (buf == "l2") {
							logic_val += pow(2, 2);
						}
						else if (buf == "l1") {
							logic_val += pow(2, 1);
						}
						else if (buf == "l0") {
							logic_val += pow(2, 0);
						}
						else
						{
							std::cout << "Error: unidentified logic signals found\n" << std::endl;
							return FALSE;
						}
					}
					// Put logic vector on the list
					vVals.push_back(logic_val);
				}
				// Display the number found for setting logic
				std::cout << "Recorded " << std::bitset<8>(logic_val).to_string() << " to the logic step." << endl;
				sss.clear();
				sss = std::stringstream(std::string(""));
			}
			wfstream.close();
		}

		// Store the data for transmit
		std::cout << "\nFill Logic step ( calling USB_Waveform_Manager::LogicFill(...) )" << std::endl;
		USB_Waveform_Manager::LogicFill(logchan, step, vTime, vVals);
		vTime.clear();
		vVals.clear();
	}
	return TRUE;
}

bool Waveform(std::string waveformfile, unsigned devnum, unsigned channel, unsigned step)
{
	// dac channel, given as '0' or '1' for each device
	unsigned dacchan = channel + 3 * devnum;

	// array for waveform values
	double darray[3];

	if (waveformfile != "") // check whether file name is valid
	{
		std::cout << "Reading waveform from " << waveformfile << "\n" << std::endl;
		std::string line;
		ifstream wfstream(waveformfile);
		std::stringstream sss;

		// array of data from file
		darray[0] = darray[1] = darray[2] = 0;

		if (wfstream.is_open()) // put into loop to read data
		{
			while (getline(wfstream, line))
			{
				std::cout << line << std::endl;
				sss << line;

				for (int j = 0; j < 3; j++)
				{
					sss >> darray[j];
				}

				// If there is NAN, this means to go to the next step instead
				if (darray[0] == -1) {
					// do nothing
				}
				else {
					// Take data from the file and place in the appropriate vector
					for (int j = 0; j < 3; j++)
					{
						switch (j)
						{
						case 0:
							vTime.push_back(darray[j]);
							break;
						case 1:
							vVals.push_back(darray[j]);
							break;
						case 2:
							vdV.push_back(darray[j]);
							break;
						default:
							std::cout << "This should not happen. Invalid position in loop" << std::endl;
						}
					}
				}
				sss.clear();
				sss = std::stringstream(std::string(""));
			}
			wfstream.close();
		}

		// Store the data for transmit
		std::cout << "\nFill Waveform ( calling USB_Waveform_Manager::WvfFill(...) )" << std::endl;
		USB_Waveform_Manager::WvfFill(dacchan, step, vTime, vVals, vdV);
		vTime.clear();
		vVals.clear();
		vdV.clear();
	}
	return TRUE;
}

bool Run(unsigned devnum, unsigned channel)
{
	USB_Waveform_Manager::Run(channel + 3 * devnum);
	return TRUE;
}
