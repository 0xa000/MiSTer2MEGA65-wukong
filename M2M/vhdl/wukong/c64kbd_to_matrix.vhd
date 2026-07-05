-------------------------------------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework — QMTECH Wukong board variant
--
-- Scanner for a real C64 keyboard attached to the Wukong's J12 header,
-- presenting the same matrix_col / matrix_col_idx interface as the MEGA65's
-- mega65kbd_to_matrix, so the rest of the M2M keyboard chain (kb_matrix_ram
-- semantics, matrix_to_keynum) is used unchanged.
--
-- The C64 matrix is electrically identical to columns 0..7 of the MEGA65/C65
-- matrix (key_num = column*8 + row), so sampled data maps 1:1. The C64 has no
-- HELP key (column 8, row 3), which the M2M Shell uses to open the on-screen
-- menu — the physical RESTORE line is mapped there instead.
--
-- Electrical handling mirrors mega65-core-wukong's wukong.vhdl: columns are
-- driven open-drain on porta (drive low or release), rows are read on portb
-- which has FPGA pullups; before each column is scanned, portb is briefly
-- driven high ("charge") to recharge the wiring capacitance, then released.
--
-- Wukong port done by 0xa000 in 2026 and licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity c64kbd_to_matrix is
   port (
      ioclock         : in  std_logic;
      clock_frequency : in  natural;                       -- Hz of ioclock

      -- C64 keyboard on J12 (tri-state buffers live in the board top)
      porta_col_n_o   : out std_logic_vector(7 downto 0);  -- '0' = pull column low, '1' = release
      portb_row_n_i   : in  std_logic_vector(7 downto 0);  -- rows, low = key pressed
      portb_charge_o  : out std_logic;                     -- '1' = drive all rows high (recharge)
      restore_n_i     : in  std_logic;                     -- separate RESTORE line, low active

      -- same interface as mega65kbd_to_matrix towards m2m_keyb
      matrix_col      : out std_logic_vector(7 downto 0) := (others => '1');
      matrix_col_idx  : in  integer range 0 to 9
   );
end entity c64kbd_to_matrix;

architecture behavioral of c64kbd_to_matrix is

   constant C_HELP_ROW : integer := 3;                     -- HELP = column 8, row 3

   type t_matrix is array (0 to 9) of std_logic_vector(7 downto 0);
   signal matrix_ram : t_matrix := (others => (others => '1'));

   type t_state is (CHARGE_ST, SETTLE_ST, SAMPLE_ST);
   signal state    : t_state := CHARGE_ST;
   signal scan_col : integer range 0 to 7 := 0;
   signal wait_cnt : natural range 0 to 65535 := 0;

begin

   -- kb_matrix_ram in the MEGA65 driver reads combinatorially; mimic that.
   matrix_col <= matrix_ram(matrix_col_idx);

   p_scan : process (ioclock)
      -- ~1 us charge, ~10 us settle: full scan of 8 columns in under 100 us,
      -- well above the 1 kHz rate matrix_to_keynum samples at
      variable v_charge_cycles : natural;
      variable v_settle_cycles : natural;
   begin
      if rising_edge(ioclock) then
         v_charge_cycles := clock_frequency / 1_000_000;
         v_settle_cycles := clock_frequency / 100_000;

         case state is
            when CHARGE_ST =>
               portb_charge_o <= '1';
               porta_col_n_o  <= (others => '1');
               if wait_cnt < v_charge_cycles then
                  wait_cnt <= wait_cnt + 1;
               else
                  wait_cnt <= 0;
                  state    <= SETTLE_ST;
               end if;

            when SETTLE_ST =>
               portb_charge_o           <= '0';
               porta_col_n_o            <= (others => '1');
               porta_col_n_o(scan_col)  <= '0';
               if wait_cnt < v_settle_cycles then
                  wait_cnt <= wait_cnt + 1;
               else
                  wait_cnt <= 0;
                  state    <= SAMPLE_ST;
               end if;

            when SAMPLE_ST =>
               matrix_ram(scan_col) <= portb_row_n_i;
               if scan_col < 7 then
                  scan_col <= scan_col + 1;
               else
                  scan_col <= 0;
               end if;
               state <= CHARGE_ST;
         end case;

         -- RESTORE acts as the MEGA65 HELP key (opens the M2M on-screen menu)
         matrix_ram(8)             <= (others => '1');
         matrix_ram(8)(C_HELP_ROW) <= restore_n_i;
         matrix_ram(9)             <= (others => '1');
      end if;
   end process p_scan;

end architecture behavioral;
