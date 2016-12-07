----------------------------------------------------------------------------------
-- Logic pulse sequencer
-- Pulls data out from memory and assumes it comes in with the following flow:
-- 	1)Logic step values and little endian duration
--		2)Rest of duration
-- If duration comes in as x"FFFF", read_addr is reset to 0 (it is up to the user to design software to insert this)
-- If duration comes in as x"FFFE", the 'running' state is paused to await for a new trigger ( " )
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity logic_processor is

	port 
	(
		-- Clock input
		clk_sys	 	  		: in std_logic;
		-- reset trigger for logic process
		iRST					: in std_logic;
		
		-- Memory data bus
		-- 16 bit data input for logic sequence data
		data_in				: in std_logic_vector(15 downto 0);
		-- Memory address location for DAC data from memory
		read_addr_out		: out std_logic_vector(9 downto 0);
		-- Input to begin running waveforms from computer trigger
		run_cmd				: in std_logic;
		
		-- Pulse sequencing ports
		-- Input logic ports
		iLogic	  	 		: in std_logic_vector(1 downto 0);
		
		-- Output logic ports
		oLogic				: out std_logic_vector(3 downto 0);
		
		-- Logic for triggering the next waveform in memory
		oDAC0_trigger		: out std_logic;
		oDAC1_trigger		: out std_logic;
		
		-- Logic derived from ADC values, designed to go 'high' when voltage below some value
		iADC0_logic			: in std_logic;
		iADC1_logic			: in std_logic;
		
		-- LEDs to display logic states
		oLED					: out std_logic_vector(5 downto 0)
	);

end entity;

architecture rtl of logic_processor is

	-- Internal copy of the address for reading from memory
	signal read_addr		: std_logic_vector((read_addr_out'length - 1) downto 0) := (others => '0');
	
	-- Internal version of output logic for singal processing
	signal Logic			: std_logic_vector(3 downto 0) := (others => '0');
	signal DAC_trigger	: std_logic_vector(1 downto 0) := (others => '0');
	
	-- Amount of clock cycles to read in new sequence
	constant READ_TIME	: std_logic_vector(23 downto 0) := x"000002";
	
begin

	-- latch read address
	read_addr_out	<= read_addr;
	
	-- push through input trigger to DAC
	oDAC0_trigger	<= iLogic(0) when DAC_trigger(0) = '0' else '1';
	oDAC1_trigger	<= iLogic(0) when DAC_trigger(1) = '0' else '1';
	
	-- ADC-measurement dependent logic
	oLogic(0)		<= Logic(0) when iADC0_logic = '0' else '1';
	oLogic(1)		<= Logic(1) when iADC1_logic = '0' else '1';
	oLogic(2)		<= Logic(2);
	oLogic(3)		<= Logic(3);
	
	-- Display logic states
	oLED(3 downto 0)	<= Logic;
	oLED(5 downto 4)	<= DAC_trigger;

	process (clk_sys, run_cmd, iLogic(1), iRST)
	
		-- States for the DAC
		type RUN_STATES 				is (RESET, IDLE, RUNNING);
		variable run_state			: RUN_STATES := RESET;
		
		-- States when pulling data out of memory
		type READ_MODES				is (READ_1, READ_2, DONE, NONE);
		variable read_mode			: READ_MODES := READ_1;
		
		-- Data communication for the logic sequence
		variable data_comm			: std_logic_vector(15 downto 0);
		
		-- The following are internal values for outputting to the DAC waveform
		-- Voltage values go 15 downto 4, we have 3 downto 0 to hold decimal points in lower bits
		variable logic_step			: std_logic_vector(7 downto 0);
		variable duration				: std_logic_vector(23 downto 0);
		-- "Reading" versions for reading memory while the DAC still runs the previous waveform cycle
		variable logic_step_read	: std_logic_vector(7 downto 0);
		variable duration_read		: std_logic_vector(23 downto 0);
		
		-- Whether or not we need to be counting
		variable timing				: std_logic;
		
	begin
	
		-- check reset flag
		if iRST = '0' then
			run_state	:= RESET;
		else
		-- Logic sequence operations
		if rising_edge(clk_sys) then
			
			case run_state is
			
			when RESET => -- Return to boot conditions
				Logic				<= (others => '0');
				DAC_trigger		<= (others => '0');
				read_addr		<= (others => '0');
				run_state		:= IDLE;
			
			when IDLE => -- Awaiting a run command			
				-- Prepare to begin reading data at start of 'running'
				read_mode		:= READ_1;
				-- No counting down when beginning to read a waveform
				timing			:= '0';
				
				-- Check if the next value on the memory register signifies the end of memory,
				-- should be in the position to which READ_1 would point in memory
				if data_in = x"FFFF" then
					read_addr	<= (others => '0');
				end if;
				
				-- Check conditions to run the waveform
				if (run_cmd = '1' OR iLogic(1) = '1') then
					run_state	:= RUNNING;
				end if;				

			when RUNNING => -- RUNNING is interpreting data at the current address
				-- Latch external waveform data
				data_comm	:= data_in;
				
				case read_mode is							
				when READ_1 =>											
					-- Read in the time to run the waveform
					logic_step_read					:= data_comm(7 downto 0);
					duration_read(7 downto 0)		:= data_comm(15 downto 8);	
					read_addr							<= read_addr + '1';
					
					-- Check if the time value flags the need to leave RUNNING
					if data_comm >= x"FFFE" then
						-- Await next run trigger
						run_state						:= IDLE;
					else
						-- Read in the starting voltage
						read_mode						:= READ_2;
					end if;
					
				when READ_2 =>
					-- Read the voltage
					duration_read(23 downto 8)		:= data_comm;
					read_addr							<= read_addr + '1';
					
					-- Handling the case that duration - read_time < 0 to make sure we have time to load the next logic in each step
					if duration < READ_TIME then
						duration							:= READ_TIME;
					end if;

					-- Read in the slope
					read_mode							:= DONE;
					
				when DONE =>
					-- Latch the read data into values used for writing to DACs
					logic_step							:= logic_step_read;
					
					-- If the next data requires waiting for a new trigger, need to allow the waveform to finish and then break to IDLE
					if data_comm >= x"FFFE" then
						duration 						:= duration_read - 1 + READ_TIME;
					else
						duration							:= duration_read - 1;
					end if;
					
					-- We are going to be timing operation time
					timing								:= '1';
					
					-- Prepared to run the waveform
					read_mode							:= NONE;					
					
				when NONE =>
					-- Case statement at NONE should end with the read address for the next waveform's time
					read_mode							:= NONE;
				end case;
				
				-- Output the logic vector
				Logic			<= logic_step(3 downto 0);
				DAC_trigger	<= logic_step(5 downto 4);
							
				if timing = '1' then
					if duration <= READ_TIME then
						--Start getting ready for the next round of data
						timing 			:= '0';
						-- Clear DAC triggers
						DAC_trigger 	<= (others => '0');
						-- Read next pulse
						read_mode		:= READ_1;
					else -- Still waiting, so loop
						duration 		:= duration - 1;
						read_mode		:= NONE;
					end if;
				end if;
				
			end case; 
		end if;
		end if;
	end process;
	
end rtl;
