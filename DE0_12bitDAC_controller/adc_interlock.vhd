----------------------------------------------------------------------------------
-- Takes 12 bit input from ADC process and triggers a logic line based on the value
-- Intended to protect devices from an unsafe source (physically, protect fiber optic cable from bad alignment)
-- Runs with the clock rate of the ADC process to check ADC values and update logic accordingly
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Physical ports to the entity
entity ADC_INTERLOCK is
	port (
			iLOGIC_CLK		: in std_logic; -- clock rate
			iADC_data		: in std_logic_vector(11 downto 0);
			iCH_count		: in std_logic_vector(2 downto 0);

			oLED				: out std_logic_vector(1 downto 0);
			oLOGIC0			: out std_logic;	-- '1' deactivates device
			oLOGIC1			: out std_logic	-- '1' deactivates device
			);
end entity;

-- Behavioral
architecture rtl of ADC_INTERLOCK is
	----------------------------------------------------------------------------------
	-- SIGNALS
	----------------------------------------------------------------------------------
	signal	LOGIC0		: std_logic := '1';					-- channel 0 value
	signal	LOGIC1		: std_logic := '1';					-- channel 1 value
	signal	led			: std_logic_vector(1 downto 0);	-- lights for each channel	

	-- threshold value, measured based on ADC values at 1/3, may need to be different for each channel
	constant ADC_THRESHOLD : std_logic_vector(11 downto 0) := "010101010101";

	----------------------------------------------------------------------------------
	-- BEGIN
	----------------------------------------------------------------------------------
begin

	-- latch outputs, "high" deactivates the physical device
	oLOGIC0 	<=	not(LOGIC0);
	oLOGIC1	<=	not(LOGIC1);
	oLED		<=	led; -- LEDs follow logic levels

	-- Interpret ADC data for logic levels
	process(iLOGIC_CLK)
	begin

		if(rising_edge(iLOGIC_CLK)) then
		
			-- update logic to be 'off' if the ADC data is below a threshold
			if(iCH_count = "000") then
				if(iADC_data < ADC_THRESHOLD) then
					-- flip logic to 'off'
					LOGIC0 <=	'0';
					led(0) <=  	'0';
				else
					LOGIC0 <=	'1';
					led(0) <= 	'1';
				end if;
			
			elsif(iCH_count = "001") then
				if(iADC_data < ADC_THRESHOLD) then
					-- flip logic to 'off'
					LOGIC1 <=	'0';
					led(1) <=  	'0';				
				else
					LOGIC1 <=	'1';
					led(1) <= 	'1';
				end if;
			end if;
			
		end if;
	end process;
	
end rtl;