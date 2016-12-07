----------------------------------------------------------------------------------
-- 12 bit output to DAC system.
-- Pulls data out from memory and assumes it comes in with the following flow:
-- 	1)Waveform duration
--		2)Starting Voltage
--		3)Slope
-- If duration comes in as x"FFFF", read_addr is reset to 0 (it is up to the user to design software to insert this)
-- If duration comes in as x"FFFE", the 'running' state is paused to await for a new trigger ( " )
-- If duration comes in as x"FFFD", then 'running' state continues but loops back to the start of memory.
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
		dac_out			: out std_logic_vector(11 downto 0) := (others => '0'); -- 12 bit DAC output
		
		-- Memory address location for DAC data from memory
		read_addr_out	: out std_logic_vector(13 downto 0);
		
		-- Logic to output new dac value
		wr_n				: out std_logic; -- Data is transparent to DAC when '0', initialize so dac is suspended
		cs_n				: out std_logic; -- chip select DAC line, DAC active when '0'
		
		-- Input to begin running waveforms from computer trigger
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
		
	-- Amount of clock cycles to read in new waveform data while running a waveform
	constant READ_TIME	: std_logic_vector(15 downto 0) := x"0004";
	
	----------------------------------------------------------------------------------
	-- BEGIN
	----------------------------------------------------------------------------------
begin
	
	-- Latch DAC on/off signals
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
		
		-- Whether or not we need to be counting
		variable timing				: std_logic;
		
	begin
		
		-- check reset flag
		if iRST = '0' then
			dac_state	:= RESET;
		else
		-- DAC operations
		if rising_edge(clk_dac) then
			
			case dac_state is
			
			when RESET => -- Return to boot conditions
				dac_out			<= (others => '0');
				read_addr		<= (others => '0');
				wr_i				<= '1';
				cs_i				<= '1';
				dac_state		:= IDLE;
				
			when IDLE => -- Awaiting a run command			
				-- Prepare to begin reading data at start of 'running'
				dac_read_mode	:= READ_T;
				-- empty out linear coefficient while IDLE
				dac_dV_i			:= (others => '0');
				-- No counting down when beginning to read a waveform
				timing			:= '0';
				
				-- Deactivate DAC write but activate chip
				wr_i				<= '0';
				cs_i				<= '1';
				
				-- Check if the next value on the memory register signifies the end of memory,
				-- should be in the position to which READ_T would point in memory
				if data_in = x"FFFF" then
					read_addr	<= (others => '0');
				end if;
				
				-- Check conditions to run the waveform
				if (run_cmd = '1' OR run_trigger = '1') then
					dac_state	:= RUNNING;
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
					-- Handling the case that time_dac_read - read_time < 0 to make sure we have time to load the next waveform
					if data_comm < READ_TIME then
						time_dac_read				:= READ_TIME;
					else
						time_dac_read				:= data_comm;
					end if;
					read_addr						<= read_addr + '1';

					-- Read in the starting voltage
					dac_read_mode					:= READ_V;
					
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
					
					-- Read the integer part
					dac_read_mode					:= READ_dV;
					
				when READ_dV =>
					-- Read linear part
					dac_dV_read(31 downto 16)	:= data_comm;
					read_addr						<= read_addr + '1';
					
					-- Finished reading in this portion of waveform
					dac_read_mode					:= DONE;
					
				when DONE =>
					-- Latch all the read data into values used for writing to DACs, timing including this cycle
					dac_out_i						:= dac_out_read;
					dac_dV_i							:= dac_dV_read;
					
					-- If the next data requires waiting for a new trigger, need to allow the waveform to finish and then break to IDLE
					if data_comm >= x"FFFE" then
						time_dac_i 					:= time_dac_read - 1 + READ_TIME;
					else
						time_dac_i					:= time_dac_read - 1;
					end if;
					
					-- If we are in "continous run" mode, loop back to the start of memory but keep running
					if data_comm = x"FFFD" then
						read_addr					<= (others => '0');
					end if;
					
					-- We are going to be timing operation time
					timing							:= '1';
					
					-- Prepared to run the waveform
					dac_read_mode					:= NONE;					
					
				when NONE =>
					-- Not currently reading anything
					-- Case statement at NONE should end with the read address for the next waveform's time
					dac_read_mode					:= NONE;
				end case;
				
				-- Generating waveform values
				-- Alter dac_val_i from coefficients for next output
				dac_out_i	:= dac_out_i + dac_dV_i;
				-- Output the voltage
				dac_out		<= dac_out_i(31 downto (32 - dac_out'length));
				
				if timing = '1' then
					if time_dac_i <= READ_TIME then
						--Start getting ready for the next round of data
						timing 				:= '0';
						-- Read in the next waveform
						dac_read_mode		:= READ_T;
						-- Check if the time value flags the need to leave RUNNING
						if data_comm >= x"FFFE" then
							-- Await next run trigger
							dac_state			:= IDLE;
							-- Prepare for next waveform
							read_addr			<= read_addr + '1';
						end if;
					else -- Still waiting, so loop
						time_dac_i 			:= time_dac_i - 1;
						dac_read_mode		:= NONE;
					end if;
				end if;
				
			end case; 
		end if;
		end if;
	end process;			
	
end rtl;
