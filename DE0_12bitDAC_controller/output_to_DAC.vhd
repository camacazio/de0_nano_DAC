----------------------------------------------------------------------------------
-- 12 bit output to DAC system.
-- Pulls data out from memory and assumes it comes in with the following flow:
-- 	1)Waveform duration
--		2)Starting Voltage
--		3)Slope
-- If duration comes in as x"FFFF", read_addr is reset to 0 (it is up to the user to design software to insert this)
-- If duration comes in as x"FFFE", the 'running' state is paused to await for a new trigger ( " )
-- If duration comes in as x"FFFD", then 'running' state continues but loops back to the start of memory. Don't give up, little DAC!
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Physical ports
entity output_to_12bitDAC is
	
	port
	(
		-- clks for incoming data and outputting to DAC
		clk_dac			: in std_logic;
		-- reset trigger for DAC process
		iRST				: in std_logic;
		
		-- Data buses
		data_in			: in std_logic_vector(15 downto 0); -- 16 bit data input for waveform data
		dac_out			: out std_logic_vector(11 downto 0); -- 12 bit DAC output
		
		-- Memory address location for DAC data from memory
		read_addr_out	: out std_logic_vector(14 downto 0);
		
		-- Logic to output new dac value
		wr_n				: out std_logic; -- Data is transparent to DAC when '0', initialize so dac is suspended
		cs_n				: out std_logic; -- chip select DAC line, DAC active when '0'
		
		-- Input to begin running waveforms from FT245
		run_cmd			: in std_logic;
		-- External logic input to begin running waveforms
		run_trigger		: in std_logic
	);

end entity;

-- Behavioral
architecture rtl of output_to_12bitDAC is
	----------------------------------------------------------------------------------
	-- SIGNALS
	----------------------------------------------------------------------------------
	
	-- Internal write enable and chip select
	signal wr_i				: std_logic := '0';
	signal cs_i				: std_logic := '0';
	
	-- Internal copy of the address for reading from memory
	signal read_addr		: std_logic_vector((read_addr_out'length - 1) downto 0) := (others => '0');
		
	-- Amount of clock cycles to read in new waveform data
	constant READ_TIME	: std_logic_vector(15 downto 0) := x"0003";
	
	----------------------------------------------------------------------------------
	-- BEGIN
	----------------------------------------------------------------------------------
begin
	
	-- Latch writing to DAC
	wr_n				<= not(wr_i);
	cs_n				<= not(cs_i);
	
	-- Latch internal read address to output
	read_addr_out	<= read_addr;
	
	-- interpret data for DAC
	process (clk_dac, run_cmd, run_trigger, iRST)
	
		-- States for the DAC
		type DAC_STATES 				is (RESET, IDLE, RUNNING);
		variable dac_state			: DAC_STATES := RESET;
		
		-- States when pulling data out of memory
		type DAC_READ_MODES			is (READ_T, READ_V, READ_dV_float, READ_dV, DONE, NONE);
		variable dac_read_mode		: DAC_READ_MODES := READ_T;
		
		-- Data communication for the waveform
		variable data_comm			: std_logic_vector(15 downto 0);
		
		-- The following are internal values for outputting to the DAC waveform
		-- Voltage values go 15 downto 4, we have 3 downto 0 to hold decimal points in lower bits
		variable dac_out_i			: std_logic_vector(31 downto 0);
		variable dac_dV_i				: std_logic_vector(31 downto 0);
		variable time_dac_i			: std_logic_vector(15 downto 0);
		-- "Reading" versions for reading memory while the DAC still runs the previous waveform cycle
		variable dac_out_read		: std_logic_vector(31 downto 0);
		variable dac_dV_read			: std_logic_vector(31 downto 0);
		variable time_dac_read		: std_logic_vector(15 downto 0);
		
		-- Counts how long a time step has been evaluating for
		variable count					: std_logic_vector(15 downto 0);
		-- Whether or not we need to be counting
		variable timing				: std_logic;
		
	begin
		if iRST = '0' then
			dac_state	:= RESET;
			
		else
		if rising_edge(clk_dac) then
			
			case dac_state is
			
			when RESET => -- Return to boot conditions
				dac_out			<= (others => '0');
				read_addr		<= (others => '0');
				wr_i				<= '0';
				cs_i				<= '0';
				dac_state		:= IDLE;
				
			
			when IDLE => -- Awaiting a run command			
				-- Prepare to begin reading data at start of 'running'
				dac_read_mode	:= READ_T;
				-- empty out linear coefficient while IDLE
				dac_dV_i			:= (others => '0');
				-- No counting down when beginning to read a waveform
				count				:= (others => '0');
				timing			:= '0';
				
				-- Deactivate DAC transparent write but activate chip
				wr_i				<= '0';
				cs_i				<= '1';
				
				-- Check if the next value on the memory register signifies the end of memory,
				-- should be in the position to which READ_T would point in memory
				if data_in = x"FFFF" then
					read_addr	<= (others => '0');
				end if;

				-- Prepare to enter the running process
				if (run_cmd = '1' or run_trigger = '1') then
					-- Start the waveform
					dac_state	:= RUNNING;
				else
					-- Wait for trigger
					dac_state	:= IDLE;
				end if;

			
			when RUNNING => -- RUNNING is interpreting data at the current address
				-- the M9K RAM updates much faster than this process, so no worries on timing with read_addr
			
				-- Activate DAC output
				wr_i			<= '1';
				-- Latch external waveform data
				data_comm	:= data_in;
				
				case dac_read_mode is							
				when READ_T =>											
					-- Read in the time to run the waveform
					time_dac_read					:= data_comm;
					read_addr						<= read_addr + '1';
					
					-- Check if the time value flags the need to leave RUNNING
					if data_comm >= x"FFFE" then
						-- Await next run trigger
						dac_state					:= IDLE;
					else
						-- Read in the starting voltage
						dac_read_mode				:= READ_V;
					end if;
					
				when READ_V =>					
					-- Read the voltage
					dac_out_read					:= data_comm & x"0000";
					read_addr						<= read_addr + '1';

					-- Read in the slope
					dac_read_mode					:= READ_dV_float;
					
				when READ_dV_float =>
					-- Read fractional linear part
					dac_dV_read(15 downto 0)	:= data_comm;
					read_addr						<= read_addr + '1';
					
					--Read the integer part
					dac_read_mode					:= READ_dV;
					
				when READ_dV =>
					-- Read linear part
					dac_dV_read(31 downto 16)	:= data_comm;
					read_addr						<= read_addr + '1';
					
					-- Finished reading in this portion of waveform
					dac_read_mode					:= DONE;
					
				when DONE =>
					-- Latch all the read data into values used for writing to DACs
					time_dac_i						:= time_dac_read;
					dac_out_i						:= dac_out_read;
					dac_dV_i							:= dac_dV_read;
					
					-- If the next data requires waiting for a new trigger, need to allow the waveform to finish and then break to IDLE
					if data_comm >= x"FFFE" then
						time_dac_i 					:= time_dac_i + READ_TIME;
					-- If we are in "continous run" mode, loop back to the start of memory but keep running
					elsif data_comm = x"FFFD" then
						read_addr					<= (others => '0');
					-- Handling the case that time_dac_i - read_time < 0 to make sure we have time to load the next waveform in each step
					elsif time_dac_i < READ_TIME then
						time_dac_i					:= READ_TIME;
					end if;
					
					-- We are going to be timing operation time
					count								:= (others => '0');
					timing							:= '1';
					
					-- Prepared to run the waveform
					dac_read_mode					:= NONE;					
					
				when NONE =>
					-- Not currently reading anything
					-- Case statement at NONE should end with the read address for the next waveform's time
					dac_read_mode					:= NONE;
				end case;
				
				-- Generating waveforms!
				-- Output the voltage
				dac_out		<= dac_out_i(31 downto (32 - dac_out'length));
				-- Alter dac_val_i from coefficients for next output
				dac_out_i	:= dac_out_i + dac_dV_i;
							
				if timing = '1' then
					if count >= (time_dac_i - READ_TIME) then
						--Start getting ready for the next round of data
						timing 				:= '0';
						dac_read_mode		:= READ_T;
					else -- Still waiting, so loop
						count 				:= count + 1;
						dac_read_mode		:= NONE;
					end if;
				end if;
				
			end case; 
		end if;
		end if;
	end process;			
	
end rtl;
