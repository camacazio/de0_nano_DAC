-- Quartus Prime VHDL Template
-- Binary Counter

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity logic_processor is

	generic
	(
		MIN_COUNT	: natural := 0;
		MAX_COUNT	: natural := 255
	);

	port 
	(
		-- Clock input
		clk_sys	   : in std_logic;
		
		-- Input logic ports
		LogicIn1   	: in std_logic;
		LogicIn2	   : in std_logic;
		
		-- Output logic ports
		LogicOut1	: out std_logic;
		LogicOut2	: out std_logic;
		LogicOut3	: out std_logic;
		LogicOut4	: out std_logic
	);

end entity;

architecture rtl of logic_processor is

	-- Signals
	signal LO1_int	: std_logic := '0';
	
begin

	-- latch output
	LogicOut1	<= LO1_int;
	LogicOut2	<= LO1_int;
	LogicOut3	<= LO1_int;
	LogicOut4	<= LO1_int;

	process (clk_sys)
		variable   cnt	: integer range MIN_COUNT to MAX_COUNT;
	begin
		if (rising_edge(clk_sys)) then

			if cnt >= (MAX_COUNT-1) then
				-- Reset the counter to 0
				cnt	:= 0;
				LO1_int	<= not(LO1_int);

			else
				-- Increment the counter if counting is enabled			   
				cnt 	:= cnt + 1;

			end if;
		end if;
		
	end process;

end rtl;