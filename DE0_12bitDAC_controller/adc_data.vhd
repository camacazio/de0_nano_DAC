----------------------------------------------------------------------------------
-- 12 bit input from ADC
-- Serial communication protocol
-- 16 clock cycles for a communication cycle, 3 bits defines the next 'read' data followed by 12 bit data
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Physical ports to the entity
entity ADC_CTRL is
	port (
			iRST			: in std_logic; -- Reset trigger
			iCLK			: in std_logic; -- Positive clock

			oadc_data	: out std_logic_vector(11 downto 0); -- ADC read-out from a channel
			oadc_chan	: out std_logic_vector(2 downto 0); -- relevant channel

			oADC_ADDR	: out std_logic;	-- setting for the desired ADC reading channel
			oCS_n			: out std_logic;	-- activate ADC chip
			oSCLK			: out std_logic;	-- serial clock
			iADC_DATA	: in std_logic	-- incoming serial data from the ADC
			);
end entity;

-- Behavioral
architecture rtl of ADC_CTRL is
	----------------------------------------------------------------------------------
	-- SIGNALS
	----------------------------------------------------------------------------------
	signal data				: std_logic;			-- channel select bit
	signal go_en			: std_logic;			-- disabled when reset is triggered
	signal count			: std_logic_vector(3 downto 0);		-- count serial clock edges up to 16
	signal n_count			: std_logic_vector(3 downto 0);		-- count serial clock falling edges up to 16
	signal ch_count		: std_logic_vector(2 downto 0);		-- declare new varible ch_count, counting to select channel.
	signal ch_reading		: std_logic_vector(2 downto 0) := (others => '0');		-- the channel currently being read; one read cycle delay
	signal adc_data		: std_logic_vector(11 downto 0);		-- data being read
	signal prv_adc_data	: std_logic_vector(11 downto 0);	-- previous channel, complete data
	signal prv_ch_read	: std_logic_vector(2 downto 0);	-- previous channel, used for data
	
	-- number of channels to be read-out
	constant NUM_CHANS	: std_logic_vector(2 downto 0) := "010";

	----------------------------------------------------------------------------------
	-- BEGIN
	----------------------------------------------------------------------------------
begin

	-- latches
	oCS_n			<= not(go_en);		-- activate ADC unless reset is flagged
	oSCLK			<= iCLK when go_en = '1' else '1'; -- Send clock signal to ADC clock if go_en is 1
	oADC_ADDR	<= data;			-- latch channel select bit
	oadc_data	<= prv_adc_data;	-- latch completed reading
	oadc_chan	<= prv_ch_read;	-- latch completed channel


-- Check for reseting the ADC reading, or to continue
process(iCLK, iRST)
begin
	if(iRST = '0') then -- If iRST is triggered
		go_en	<=	'0'; 
	else
		if rising_edge(iCLK) then -- at the first positive clock edge
			go_en		<='1';
		end if;
	end if;
end process;

-- counting positive edges of clock
process(iCLK, go_en)	-- At positive clock edge or go_en is turned off.
begin
	if(go_en = '0') then		-- If go_en = 0 then clear the count
		count	<=	(others => '0');	
	else
		if rising_edge(iCLK)	then	-- else increment count at each clock cycle, when clock is on HIGH.
			count	<=	count + 1;
		end if;
	end if;
end process;

-- Latch counting for the negative edges of clock
process(iCLK)	-- Update negative count at falling clock edge
begin
	if(falling_edge(iCLK)) then		-- at clock on LOW.
		n_count <= count;	-- load count to n_count at each neg clock cycle
	end if;
end process;

-- Loops through channels, returning the data
process(iCLK, go_en)	-- ch_count will increment at each loop of count 0 to 15 of ADC reading.
begin
	if(go_en = '0') then		-- If go_en = 0 then reset the channel count
		ch_count <= (others => '0');
	else
		if(falling_edge(iCLK)) then
			if(count = 1) then
				ch_reading	<= ch_count;
				if(ch_count < (NUM_CHANS)) then	-- count ch_count up to at most 8 channels
					ch_count <= ch_count+1;
				else
					ch_count <= (others => '0');
				end if;
			end if;
			if (count = 2) then
				data	<= ch_count(2);
			elsif (count = 3)	then
				data	<=	ch_count(1);
			elsif (count = 4) then
				data	<=	ch_count(0);
			else
				data	<=	'0';
			end if;
		end if;
	end if;
end process;

-- Take in the ADC data as it gets clocked in on the negative edge
process(iCLK, go_en) -- Take in ADC bit stream
begin
	if(go_en = '0') then	-- If go_en is low, clear ADC data
		adc_data	<=	(others => '1');
	else
		if(rising_edge(iCLK)) then	-- At positive clock edge
											-- retrieve ADC data from MSB to LSB
			if	(n_count = 4) then
				adc_data(11)	<=	iADC_DATA;
			elsif	(n_count = 5) then
				adc_data(10)	<=	iADC_DATA;
			elsif (n_count = 6) then
				adc_data(9)		<=	iADC_DATA;
			elsif (n_count = 7) then
				adc_data(8)		<=	iADC_DATA;
			elsif	(n_count = 8) then
				adc_data(7)		<=	iADC_DATA;
			elsif	(n_count = 9) then
				adc_data(6)		<=	iADC_DATA;
			elsif (n_count = 10) then
				adc_data(5)		<=	iADC_DATA;
			elsif (n_count = 11) then
				adc_data(4)		<=	iADC_DATA;
			elsif (n_count = 12) then
				adc_data(3)		<=	iADC_DATA;
			elsif (n_count = 13) then
				adc_data(2)		<=	iADC_DATA;
			elsif (n_count = 14) then
				adc_data(1)		<=	iADC_DATA;
			elsif (n_count = 15) then
				adc_data(0)		<=	iADC_DATA;
			elsif (n_count = 0) then
				-- update the ADC value and the channel information for the next cycle
				prv_ch_read		<= ch_reading;
				prv_adc_data	<= adc_data;
			end if;
		end if;
	end if;
end process;

end rtl; 
