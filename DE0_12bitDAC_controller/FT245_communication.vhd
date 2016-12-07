----------------------------------------------------------------------------------
-- Communication with FT245 for USB to 8-bit parrallel interface
-- Handles communication with computer and sends data to rest of system
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FT245Comm is

	Port ( 
		-- Clocks
		clk_comm			: in 		std_logic;
		
		-- USB to FIFO communication: FT245RL
		comm_data		: in		std_logic_vector(7 downto 0);		-- Unidirectional data bus
		comm_rxfl		: in		std_logic;								-- FIFO has data for read, default '1'
		comm_rdl			: out		std_logic := '1';						-- Fetch from FIFO, default '1'
		
		-- Data output word
		data_q			: out		std_logic_vector(15 downto 0);	-- Word for the rest of the system
		-- Address for memory location for data
		addr_comm_q		: out		std_logic_vector(13 downto 0);	-- address for writing to the M9K RAM
		
		-- Enable for different DAC memory blocks
		chan0_wren		: out		std_logic;
		chan1_wren		: out		std_logic;
		logic_wren		: out		std_logic;
		
		-- USB command to run operations in rest of system
		run_wave0		: out		std_logic;
		run_wave1		: out		std_logic;
		run_logic		: out		std_logic
	);
	
end entity;

architecture Behavioral of FT245Comm is
	----------------------------------------------------------------------------------
	-- SIGNALS
	----------------------------------------------------------------------------------	
	
	-- Internal copy of word of data
	signal data_out			: std_logic_vector(15 downto 0) := (others => '0');
	-- Steps through the write port of the M9K RAM
	signal addr_comm			: std_logic_vector((addr_comm_q'length - 1) downto 0) := (others => '0');
	
	-- Sets the channel for data communication (whether TTL sequence or DAC memory)
	signal channel				: std_logic_vector(7 downto 0) := (others => '0');
	-- Enables writing to the chosen channel's M9K
	signal chanx_wren			: std_logic := '0';
	
	-- Enables running sequences to the chosen channel
	signal run_wavex			: std_logic := '0';
		
	----------------------------------------------------------------------------------
	-- BEGIN
	----------------------------------------------------------------------------------
begin
	
	-- Latch data
	data_q		<= data_out;
	-- Latch memory address
	addr_comm_q	<= addr_comm;
	
	-- Latch the 'write enable' for memory depending on channel
	chan0_wren	<= chanx_wren when channel = x"00" else '0';
	chan1_wren	<= chanx_wren when channel = x"01" else '0';
	-- For the case that data is being transmitted for pulse sequencing
	logic_wren	<= chanx_wren when channel = x"02" else '0';
	
	-- Running the next waveform via communication channel
	run_wave0	<= run_wavex when channel = x"00" else '0';
	run_wave1	<= run_wavex when channel = x"01" else '0';
	-- run logic sequencing
	run_logic	<= run_wavex when channel = x"02" else '0';
	
	process (clk_comm, comm_rxfl)
		
		-- Define FSM
		type 		COMM_STATES 		is (RESET, IDLE, RECEIVE);
		-- Command states have multiple copies of commands for grabbing 1 byte at a time
		type		COMMANDS				is (NONE, BURST1, BURST2, WRITE1, WRITE2, SETADDR1, SETADDR2, CHANNEL1);
		
		variable comm_state			: COMM_STATES := RESET;
		variable	command				: COMMANDS := NONE;
		
		-- data byte on each transmit
		variable data_in				: std_logic_vector(7 downto 0);
		-- For counting number of words to take in on a burst write command
		variable count					: std_logic_vector(15 downto 0);
		-- Used to siginify a need to walk through address locations
		variable inc_addr				: std_logic;
		-- Counter for the run_wave trigger for slower processes
		variable run_count			: std_logic_vector(1 downto 0);
		
		-- Command states list
		
		-- Commands for writing data to memory
     	-- Sets burst length
		constant CMD_BURST			: std_logic_vector(7 downto 0) := x"00";
		-- Write waveform data
		constant CMD_WRITESINGLE 	: std_logic_vector(7 downto 0) := x"01";
		constant CMD_WRITEBURST 	: std_logic_vector(7 downto 0) := x"02";
		-- Input the address to begin writing in memory
		constant CMD_SETADDR	 		: std_logic_vector(7 downto 0) := x"03";
		-- Select system channel to receive data
		constant CMD_CHANNEL			: std_logic_vector(7 downto 0) := x"04";		
		-- Run the wave via USB connection
		constant CMD_RUNWAVE			: std_logic_vector(7 downto 0) := x"05";
		
	begin			
		if rising_edge(clk_comm) then
			case comm_state is
			when RESET =>
				-- Clear values to default
				comm_rdl				<= '1';
				addr_comm			<= (others => '0');
				chanx_wren			<= '0';
				run_wavex			<= '0';
				count					:= (others => '0');
				run_count			:= (others => '0');
				inc_addr				:= '0';
				command 				:= NONE;
				
				-- Return to IDLE
				comm_state 		:= IDLE;
				
			when IDLE =>
				-- IDLE until data transfer with FIFO or other processes is ready/complete
				
				-- Are we ready/writing or just staying in idle
				if comm_rxfl = '0' then
					comm_rdl			<= '0'; -- Take the read line low to take data. Data available on the next clock cycle.
					comm_state		:= RECEIVE;
				else
					-- Stay in IDLE
					comm_rdl			<= '1'; -- default
					comm_state 		:= IDLE;
				end if;
				
				-- At end of WRITE2, wren line should have been raised, now clear here
				chanx_wren		<= '0';
				-- Running waveforms, reset the trigger after a wait period
				if run_wavex = '1' then
					run_count	:= run_count + 1;
					if run_count = 0 then
						run_wavex	<= '0';
					end if;
				end if;
				
				-- If flagged, increment address for writing location
				addr_comm 		<= addr_comm + inc_addr;
				inc_addr			:= '0';
		
			-- RECEIVE cycle. RECEIVE->IDLE->RECEIVE->...->IDLE
		   when RECEIVE =>
				-- Data is available
				data_in			:= comm_data;	-- Latch data
				
				-- Raise the Rd line and proceed to command "RECEIVE1". 
				-- "RECEIVE1" will trigger the "RECEIVE2" state if more data is available.
				comm_rdl 		<= '1';
				comm_state 		:= IDLE;
						
				-- Interpret or route incoming data.
				case command is
				when NONE =>
					-- Incoming is a command
					case data_in is
					
						when CMD_BURST => -- Following two bytes is the burst count for writing a burst of data
							command 			:= BURST1;
							
						when CMD_WRITESINGLE => -- Following two bytes are data to be written into the memory
							count 			:= CONV_STD_LOGIC_VECTOR(1,count'length); -- Burst count is 1;
							command 			:= WRITE1;
							
						when CMD_WRITEBURST => -- Interpret each pair of subsequent bytes as a write and decrement burst count until 0
							if count > 0 then
								command 		:= WRITE1;
							else
								command 		:= NONE;
							end if;
							
						when CMD_SETADDR => -- Following two bytes is the address for the start of memory storage
							command 			:= SETADDR1;
							
						when CMD_CHANNEL => -- Following byte sets the communication channel for a device
							command			:= CHANNEL1;
							
						when CMD_RUNWAVE => -- Flag to run waveforms or other operations
							run_wavex		<= '1';
							command	 		:= NONE;					
						
						-- unkown command; ignore
						when others =>
							command 			:= NONE;
							
					end case;
					
					
				--Begin handling of the COMMAND_STATES cases
					
				-- CMD_BURST sequence
				when BURST1 =>
					-- First of two bytes. Little Endian
					count					 		:= x"00" & data_in;
					command 						:= BURST2;
				when BURST2 =>
					-- Second of two bytes. Little Endian
					count							:= data_in & count(7 downto 0);
					command			 			:= NONE; -- Done with this command	
					
				-- CMD_WRITESINGLE and CMD_WRITEBURST.
				when WRITE1 =>
					-- Place data on register
					data_out						<= x"00" & data_in;
					-- We need a second byte to finish the data
					command						:= WRITE2;		
				when WRITE2 =>
					-- Place data on register
					data_out						<= data_in & data_out(7 downto 0);
					-- Prepare stepping to the next memory location
					chanx_wren					<= '1';
					inc_addr						:= '1';
					-- Decrement count, none command when done, else repeat.
					count							:= count - 1;
					if count < 1 then
						-- Done with writing to memory so allow rest of process to function
						command 					:= NONE; -- Done with write command
					else
						command					:= WRITE1; -- Read more data from FIFO as it becomes available.
					end if;
					
				-- CMD_SETLEN sequence
				when SETADDR1 =>
					-- First of two bytes. Little Endian
					addr_comm(7 downto 0)	<= data_in;
					command						:= SETADDR2;
				when SETADDR2 =>
					-- Second of two bytes. Little Endian
					addr_comm					<= data_in(addr_comm'LENGTH-9 downto 0) & addr_comm(7 downto 0);
					command			 			:= NONE; -- Done with this command
					
				-- CMD_CHANNEL sequence
				when CHANNEL1 =>
					-- set the communication channel
					channel						<= data_in;
					command						:= NONE;
										
				when others =>
					command	 					:= NONE;
					
				end case;
			end case;
		end if;
	end process;
	
end Behavioral;