----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework — QMTECH Wukong board variant
--
-- Keyboard controller, adapted from m2m_keyb.vhd: the MEGA65 smart keyboard
-- driver (kio serial protocol) is replaced by a scanner for a real C64
-- keyboard on the Wukong's J12 header. Everything downstream (matrix format,
-- matrix_to_keynum, the QNICE special key register) is identical to upstream.
--
-- The MEGA65 keyboard's RGB power/drive LEDs do not exist here; the led
-- inputs are kept in the entity for interface compatibility and the on/off
-- state is exposed for the Wukong's plain board LEDs instead.
--
-- Runs in the clock domain of the core.
--
-- Wukong port done by 0xa000 in 2026, based on m2m_keyb.vhd by sy2002 and
-- MJoergen, licensed under GPL v3
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity m2m_keyb_wukong is
   generic (
      SCAN_FREQUENCY       : integer := 1000                   -- keyboard scan frequency in Herz, default: 1 kHz
   );
   port (
      clk_main_i           : in std_logic;                     -- core clock
      clk_main_speed_i     : in natural;                       -- speed of core clock in Hz

      -- interface to the C64 keyboard on J12
      porta_col_n_o        : out std_logic_vector(7 downto 0); -- '0' = pull column low, '1' = release
      portb_row_n_i        : in  std_logic_vector(7 downto 0); -- rows, low = key pressed
      portb_charge_o       : out std_logic;                    -- '1' = drive all rows high (recharge)
      restore_n_i          : in  std_logic;                    -- RESTORE line, low active (acts as Help)

      -- interface to the core
      enable_core_i        : in std_logic;                     -- 0 = core is decoupled from the keyboard, 1 = standard operation
      key_num_o            : out integer range 0 to 79;        -- cycles through all keys with SCAN_FREQUENCY
      key_pressed_n_o      : out std_logic;                    -- low active: debounced feedback: is kb_key_num_o pressed right now?

      -- drive led status (no keyboard LEDs on the Wukong; see board top)
      power_led_i          : in std_logic;
      drive_led_i          : in std_logic;

      -- interface to QNICE: used by the firmware and the Shell (see sysdef.asm for details)
      qnice_keys_n_o       : out std_logic_vector(15 downto 0)
   );
end m2m_keyb_wukong;

architecture beh of m2m_keyb_wukong is

signal matrix_col          : std_logic_vector(7 downto 0);
signal matrix_col_idx      : integer range 0 to 9 := 0;
signal key_num             : integer range 0 to 79;
signal key_status_n        : std_logic;
signal keys_n              : std_logic_vector(15 downto 0) := x"FFFF"; -- low active, "no key pressed"

begin
   -- output the keyboard interface for the core
   key_num_o         <= key_num;
   key_pressed_n_o   <= key_status_n when enable_core_i else '1';

   -- output the keyboard interface for QNICE
   qnice_keys_n_o    <= keys_n;

   c64driver : entity work.c64kbd_to_matrix
   port map
   (
       ioclock          => clk_main_i,
       clock_frequency  => clk_main_speed_i,

       porta_col_n_o    => porta_col_n_o,
       portb_row_n_i    => portb_row_n_i,
       portb_charge_o   => portb_charge_o,
       restore_n_i      => restore_n_i,

       matrix_col       => matrix_col,
       matrix_col_idx   => matrix_col_idx
   );

   m65matrix_to_keynum : entity work.matrix_to_keynum
   generic map
   (
      scan_frequency    => SCAN_FREQUENCY
   )
   port map
   (
      clk               => clk_main_i,
      clock_frequency   => clk_main_speed_i,
      reset_in          => '0',

      matrix_col => matrix_col,
      matrix_col_idx => matrix_col_idx,

      m65_key_num => key_num,
      m65_key_status_n => key_status_n,

      suppress_key_glitches => '1',
      suppress_key_retrigger => '0',

      bucky_key => open
   );

   matrix_col_idx_handler : process(clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         if matrix_col_idx < 9 then
           matrix_col_idx <= matrix_col_idx + 1;
         else
           matrix_col_idx <= 0;
         end if;
      end if;
   end process;

   -- make qnice_keys_o a register and fill it
   -- see sysdef.asm for the key-to-bit mapping
   handle_qnice_keys : process(clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         case key_num is
            when 73        => keys_n(0) <= key_status_n;     -- Cursor up
            when 7         => keys_n(1) <= key_status_n;     -- Cursor down
            when 74        => keys_n(2) <= key_status_n;     -- Cursor left
            when 2         => keys_n(3) <= key_status_n;     -- Cursor right
            when 1         => keys_n(4) <= key_status_n;     -- Return
            when 60        => keys_n(5) <= key_status_n;     -- Space
            when 63        => keys_n(6) <= key_status_n;     -- Run/Stop
            when 67        => keys_n(7) <= key_status_n;     -- Help
            when 4         => keys_n(8) <= key_status_n;     -- F1
            when 5         => keys_n(9) <= key_status_n;     -- F3
            when others    => null;
         end case;
      end if;
   end process;
end beh;
