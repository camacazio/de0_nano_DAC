-- Basic Channel number fan-out Register

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

entity channel_setting is

	-- integers for channel labels
	generic
	(
		channel0	: integer := 0;
		channel1 : integer := 1
	);
	
	port 
	(
		clk		: in std_logic;
		-- signals for channel labels for various entities
		chan0		: out std_logic_vector(7 downto 0);
		chan1	   : out std_logic_vector(7 downto 0)
	);

end entity;

architecture rtl of channel_setting is

begin

	process (clk)
	begin
		if (rising_edge(clk)) then
			
			-- latch channels
			chan0 <= conv_std_logic_vector(channel0, chan0'length);
			chan1 <= conv_std_logic_vector(channel1, chan1'length);
			
		end if;
	end process;

end rtl;
