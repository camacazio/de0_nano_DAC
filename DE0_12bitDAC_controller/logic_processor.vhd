-- Quartus Prime VHDL Template
-- Binary Counter

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity logic_processor is

	port 
	(
		-- Clock input
		clk_sys	   : in std_logic;
		
		-- Input logic ports
		LogicIn1   	: in std_logic;
		LogicIn2	   : in std_logic;
		
		-- Output logic ports
		LogicOut1	: out std_logic := '0';
		LogicOut2	: out std_logic := '0';
		LogicOut3	: out std_logic := '0';
		LogicOut4	: out std_logic := '0'
	);

end entity;

architecture rtl of logic_processor is
	
begin

	-- latch outputs?

	process (clk_sys)
	begin

		LogicOut1	<= '0';
		LogicOut2	<= '0';
		LogicOut3	<= '0';
		LogicOut4	<= '0';
		
	end process;

end rtl;