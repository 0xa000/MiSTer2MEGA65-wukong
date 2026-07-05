-------------------------------------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework — QMTECH Wukong board variant
--
-- Board clock conditioner: the Wukong provides a 50 MHz oscillator, while the
-- whole M2M framework (clk_m2m, video_out_clock, reset_manager, democore clk)
-- is written against the MEGA65's 100 MHz board clock. One PLL doubles the
-- board clock so everything downstream stays byte-identical to upstream M2M.
--
-- Wukong port done by 0xa000 in 2026 and licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clk_wukong is
   port (
      sys_clk_50_i  : in  std_logic;   -- Wukong 50 MHz oscillator
      sys_clk_100_o : out std_logic;   -- M2M 100 MHz board clock
      sys_locked_o  : out std_logic
   );
end entity clk_wukong;

architecture rtl of clk_wukong is

signal clk_fb       : std_logic;
signal clk_100_pll  : std_logic;

begin

   -- VCO = 50 MHz * 20 = 1000 MHz; 1000 / 10 = 100 MHz
   i_pll_sys : PLLE2_BASE
      generic map (
         BANDWIDTH          => "OPTIMIZED",
         CLKFBOUT_MULT      => 20,
         CLKFBOUT_PHASE     => 0.000,
         CLKIN1_PERIOD      => 20.0,        -- INPUT @ 50 MHz
         CLKOUT0_DIVIDE     => 10,          -- 100 MHz
         CLKOUT0_DUTY_CYCLE => 0.500,
         CLKOUT0_PHASE      => 0.000,
         DIVCLK_DIVIDE      => 1,
         REF_JITTER1        => 0.010,
         STARTUP_WAIT       => "FALSE"
      )
      port map (
         CLKFBIN  => clk_fb,
         CLKFBOUT => clk_fb,
         CLKIN1   => sys_clk_50_i,
         CLKOUT0  => clk_100_pll,
         LOCKED   => sys_locked_o,
         PWRDWN   => '0',
         RST      => '0'
      ); -- i_pll_sys

   sys_clk_bufg : BUFG
      port map (
         I => clk_100_pll,
         O => sys_clk_100_o
      );

end architecture rtl;
