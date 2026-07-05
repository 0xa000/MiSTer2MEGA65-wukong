----------------------------------------------------------------------------------
-- MiSTer2MEGA65 — QMTECH Wukong board top
--
-- Board layer for the Wukong (XC7A100T, 50 MHz oscillator, DDR3, HDMI out,
-- C64 keyboard on J12, joysticks on J10/J11 PMODs, one SD card slot).
--
-- Port name conventions follow the mega65-core-wukong XDC so the pin
-- constraints can be shared between both projects.
--
-- Compared to the MEGA65 board tops there is: no VGA/VDAC, no analog audio
-- (sound is embedded in HDMI), no paddles, no IEC, no cartridge port, no I2C
-- peripherals, no second SD slot. LEDs and buttons are active low.
--
-- Wukong port done by 0xa000 in 2026, based on top_mega65-r6.vhd by MJoergen
-- and sy2002, licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;

entity top_wukong is
port (
   -- Onboard crystal oscillator = 50 MHz
   clk_in                  : in    std_logic;

   -- Buttons (active low)
   reset_button            : in    std_logic;

   -- USB-RS232 Interface
   rsrx                    : in    std_logic;
   uart_txd                : out   std_logic;

   -- HDMI
   tmds_data_p             : out   std_logic_vector(2 downto 0);
   tmds_data_n             : out   std_logic_vector(2 downto 0);
   tmds_clk_p              : out   std_logic;
   tmds_clk_n              : out   std_logic;

   -- C64 keyboard on J12; RESTORE is a separate line
   restore_key             : in    std_logic;
   porta_pins              : inout std_logic_vector(7 downto 0);
   portb_pins              : inout std_logic_vector(7 downto 0);

   -- SD card (single slot)
   int_sd_reset            : out   std_logic;
   int_sd_clock            : out   std_logic;
   int_sd_mosi             : out   std_logic;
   int_sd_miso             : in    std_logic;

   -- Joysticks on J10 (port 1) and J11 (port 2), active low, board pullups
   fa_up                   : in    std_logic;
   fa_down                 : in    std_logic;
   fa_left                 : in    std_logic;
   fa_right                : in    std_logic;
   fa_fire                 : in    std_logic;
   fb_up                   : in    std_logic;
   fb_down                 : in    std_logic;
   fb_left                 : in    std_logic;
   fb_right                : in    std_logic;
   fb_fire                 : in    std_logic;

   -- DDR3 256MB (Micron MT41K128M16JT-125:K)
   ddr3_clk_p              : out   std_logic;
   ddr3_clk_n              : out   std_logic;
   ddr3_reset_n            : out   std_logic;
   ddr3_cke                : out   std_logic;
   ddr3_ras_n              : out   std_logic;
   ddr3_cas_n              : out   std_logic;
   ddr3_we_n               : out   std_logic;
   ddr3_addr               : out   std_logic_vector(13 downto 0);
   ddr3_ba                 : out   std_logic_vector(2 downto 0);
   ddr3_dq                 : inout std_logic_vector(15 downto 0);
   ddr3_dqs_p              : inout std_logic_vector(1 downto 0);
   ddr3_dqs_n              : inout std_logic_vector(1 downto 0);
   ddr3_dm                 : out   std_logic_vector(1 downto 0);
   ddr3_odt                : out   std_logic;

   -- On board LEDs (active low)
   led0                    : out   std_logic;
   led1                    : out   std_logic
);
end entity top_wukong;

architecture synthesis of top_wukong is

   signal clk_100     : std_logic;             -- M2M 100 MHz board clock

   signal main_clk    : std_logic;
   signal main_rst    : std_logic;
   signal qnice_clk   : std_logic;
   signal qnice_rst   : std_logic;

   -- keyboard
   signal kb_porta_col_n    : std_logic_vector(7 downto 0);
   signal kb_portb_charge   : std_logic;

   --------------------------------------------------------------------------------------------
   -- main_clk (MiSTer core's clock)
   ---------------------------------------------------------------------------------------------

   -- QNICE control and status register
   signal main_qnice_reset       : std_logic;
   signal main_qnice_pause       : std_logic;

   signal main_reset_m2m         : std_logic;
   signal main_reset_core        : std_logic;

   -- keyboard handling (incl. drive led)
   signal main_key_num           : integer range 0 to 79;
   signal main_key_pressed_n     : std_logic;
   signal main_power_led         : std_logic;
   signal main_power_led_col     : std_logic_vector(23 downto 0);
   signal main_drive_led         : std_logic;
   signal main_drive_led_col     : std_logic_vector(23 downto 0);

   -- QNICE On Screen Menu selections
   signal main_osm_control_m     : std_logic_vector(255 downto 0);

   -- QNICE general purpose register
   signal main_qnice_gp_reg      : std_logic_vector(255 downto 0);

   -- signed audio from the core
   signal main_audio_l           : signed(15 downto 0);
   signal main_audio_r           : signed(15 downto 0);

   -- Video output from Core
   signal video_clk              : std_logic;
   signal video_rst              : std_logic;
   signal video_ce               : std_logic;
   signal video_ce_ovl           : std_logic;
   signal video_red              : std_logic_vector(7 downto 0);
   signal video_green            : std_logic_vector(7 downto 0);
   signal video_blue             : std_logic_vector(7 downto 0);
   signal video_vs               : std_logic;
   signal video_hs               : std_logic;
   signal video_hblank           : std_logic;
   signal video_vblank           : std_logic;

   -- Joysticks
   signal main_joy1_up_n_in      : std_logic;
   signal main_joy1_down_n_in    : std_logic;
   signal main_joy1_left_n_in    : std_logic;
   signal main_joy1_right_n_in   : std_logic;
   signal main_joy1_fire_n_in    : std_logic;

   signal main_joy1_up_n_out     : std_logic;
   signal main_joy1_down_n_out   : std_logic;
   signal main_joy1_left_n_out   : std_logic;
   signal main_joy1_right_n_out  : std_logic;
   signal main_joy1_fire_n_out   : std_logic;

   signal main_joy2_up_n_in      : std_logic;
   signal main_joy2_down_n_in    : std_logic;
   signal main_joy2_left_n_in    : std_logic;
   signal main_joy2_right_n_in   : std_logic;
   signal main_joy2_fire_n_in    : std_logic;

   signal main_joy2_up_n_out     : std_logic;
   signal main_joy2_down_n_out   : std_logic;
   signal main_joy2_left_n_out   : std_logic;
   signal main_joy2_right_n_out  : std_logic;
   signal main_joy2_fire_n_out   : std_logic;

   signal main_pot1_x            : std_logic_vector(7 downto 0);
   signal main_pot1_y            : std_logic_vector(7 downto 0);
   signal main_pot2_x            : std_logic_vector(7 downto 0);
   signal main_pot2_y            : std_logic_vector(7 downto 0);
   signal main_rtc               : std_logic_vector(64 downto 0);

   ---------------------------------------------------------------------------------------------
   -- HyperRAM clock domain (the DDR3 presents the HyperRAM controller's Avalon interface)
   ---------------------------------------------------------------------------------------------

   signal hr_clk                 : std_logic;
   signal hr_rst                 : std_logic;
   signal hr_core_write          : std_logic;
   signal hr_core_read           : std_logic;
   signal hr_core_address        : std_logic_vector(31 downto 0);
   signal hr_core_writedata      : std_logic_vector(15 downto 0);
   signal hr_core_byteenable     : std_logic_vector(1 downto 0);
   signal hr_core_burstcount     : std_logic_vector(7 downto 0);
   signal hr_core_readdata       : std_logic_vector(15 downto 0);
   signal hr_core_readdatavalid  : std_logic;
   signal hr_core_waitrequest    : std_logic;
   signal hr_low                 : std_logic;
   signal hr_high                : std_logic;

   signal ddr3_calib_complete    : std_logic;

   ---------------------------------------------------------------------------------------------
   -- qnice_clk
   ---------------------------------------------------------------------------------------------

   -- Video and audio mode control
   signal qnice_dvi              : std_logic;
   signal qnice_video_mode       : video_mode_type;
   signal qnice_scandoubler      : std_logic;
   signal qnice_csync            : std_logic;
   signal qnice_audio_mute       : std_logic;
   signal qnice_audio_filter     : std_logic;
   signal qnice_zoom_crop        : std_logic;
   signal qnice_ascal_mode       : std_logic_vector(1 downto 0);
   signal qnice_ascal_polyphase  : std_logic;
   signal qnice_ascal_triplebuf  : std_logic;
   signal qnice_retro15kHz       : std_logic;
   signal qnice_osm_cfg_scaling  : std_logic_vector(8 downto 0);

   -- flip joystick ports
   signal qnice_flip_joyports    : std_logic;

   -- QNICE On Screen Menu selections
   signal qnice_osm_control_m    : std_logic_vector(255 downto 0);

   -- QNICE general purpose register
   signal qnice_gp_reg           : std_logic_vector(255 downto 0);

   -- QNICE MMIO 4k-segmented access to RAMs, ROMs and similarily behaving devices
   signal qnice_ramrom_dev       : std_logic_vector(15 downto 0);
   signal qnice_ramrom_addr      : std_logic_vector(27 downto 0);
   signal qnice_ramrom_data_out  : std_logic_vector(15 downto 0);
   signal qnice_ramrom_data_in   : std_logic_vector(15 downto 0);
   signal qnice_ramrom_ce        : std_logic;
   signal qnice_ramrom_we        : std_logic;
   signal qnice_ramrom_wait      : std_logic;

begin

   ---------------------------------------------------------------------------------------------
   -- 50 MHz board oscillator -> M2M's 100 MHz board clock
   ---------------------------------------------------------------------------------------------

   i_clk_wukong : entity work.clk_wukong
      port map (
         sys_clk_50_i  => clk_in,
         sys_clk_100_o => clk_100,
         sys_locked_o  => open
      ); -- i_clk_wukong

   ---------------------------------------------------------------------------------------------
   -- C64 keyboard: open-drain column drivers, row inputs with charge pump
   -- (see mega65-core-wukong's wukong.vhdl for the electrical background)
   ---------------------------------------------------------------------------------------------

   porta_gen : for i in 0 to 7 generate
      porta_pins(i) <= '0' when kb_porta_col_n(i) = '0' else 'Z';
   end generate porta_gen;

   portb_pins <= (others => '1') when kb_portb_charge = '1' else (others => 'Z');

   ---------------------------------------------------------------------------------------------
   -- LEDs (active low): led0 = power led from the core,
   -- led1 = drive led, lit solid while the DDR3 has not finished calibration
   ---------------------------------------------------------------------------------------------

   led0 <= not main_power_led;
   led1 <= not (main_drive_led or (not ddr3_calib_complete));

   -----------------------------------------------------------------------------------------
   -- MiSTer2MEGA framework
   -----------------------------------------------------------------------------------------

   i_framework : entity work.framework_wukong
   generic map (
      G_BOARD => "WUKONG"
   )
   port map (
      -- Connect to I/O ports
      clk_i                   => clk_100,
      reset_n_i               => reset_button,       -- button is active low
      uart_rxd_i              => rsrx,
      uart_txd_o              => uart_txd,
      vga_red_o               => open,
      vga_green_o             => open,
      vga_blue_o              => open,
      vga_hs_o                => open,
      vga_vs_o                => open,
      vdac_clk_o              => open,
      vdac_sync_n_o           => open,
      vdac_blank_n_o          => open,
      tmds_data_p_o           => tmds_data_p,
      tmds_data_n_o           => tmds_data_n,
      tmds_clk_p_o            => tmds_clk_p,
      tmds_clk_n_o            => tmds_clk_n,
      kb_porta_col_n_o        => kb_porta_col_n,
      kb_portb_row_n_i        => portb_pins,
      kb_portb_charge_o       => kb_portb_charge,
      kb_restore_n_i          => restore_key,
      -- The single Wukong SD slot maps to M2M's "external" slot, which has
      -- precedence in the firmware's auto mode; the internal slot reads "no card"
      sd_reset_o              => int_sd_reset,
      sd_clk_o                => int_sd_clock,
      sd_mosi_o               => int_sd_mosi,
      sd_miso_i               => int_sd_miso,
      sd_cd_i                 => '0',                -- low active: card present
      sd2_reset_o             => open,
      sd2_clk_o               => open,
      sd2_mosi_o              => open,
      sd2_miso_i              => '1',
      sd2_cd_i                => '1',                -- low active: no card
      joy_1_up_n_i            => fa_up,
      joy_1_down_n_i          => fa_down,
      joy_1_left_n_i          => fa_left,
      joy_1_right_n_i         => fa_right,
      joy_1_fire_n_i          => fa_fire,
      joy_1_up_n_o            => open,               -- joystick pins are input-only on the Wukong
      joy_1_down_n_o          => open,
      joy_1_left_n_o          => open,
      joy_1_right_n_o         => open,
      joy_1_fire_n_o          => open,
      joy_2_up_n_i            => fb_up,
      joy_2_down_n_i          => fb_down,
      joy_2_left_n_i          => fb_left,
      joy_2_right_n_i         => fb_right,
      joy_2_fire_n_i          => fb_fire,
      joy_2_up_n_o            => open,
      joy_2_down_n_o          => open,
      joy_2_left_n_o          => open,
      joy_2_right_n_o         => open,
      joy_2_fire_n_o          => open,
      paddle_i                => (others => '0'),    -- no paddles on the Wukong
      paddle_drain_o          => open,
      ddr3_clk_p_o            => ddr3_clk_p,
      ddr3_clk_n_o            => ddr3_clk_n,
      ddr3_reset_n_o          => ddr3_reset_n,
      ddr3_cke_o              => ddr3_cke,
      ddr3_ras_n_o            => ddr3_ras_n,
      ddr3_cas_n_o            => ddr3_cas_n,
      ddr3_we_n_o             => ddr3_we_n,
      ddr3_addr_o             => ddr3_addr,
      ddr3_ba_o               => ddr3_ba,
      ddr3_dq_io              => ddr3_dq,
      ddr3_dqs_p_io           => ddr3_dqs_p,
      ddr3_dqs_n_io           => ddr3_dqs_n,
      ddr3_dm_o               => ddr3_dm,
      ddr3_odt_o              => ddr3_odt,
      ddr3_calib_complete_o   => ddr3_calib_complete,

      -- Connect to CORE
      qnice_clk_o             => qnice_clk,
      qnice_rst_o             => qnice_rst,
      main_clk_i              => main_clk,
      main_rst_i              => main_rst,
      main_qnice_reset_o      => main_qnice_reset,
      main_qnice_pause_o      => main_qnice_pause,
      main_reset_m2m_o        => main_reset_m2m,
      main_reset_core_o       => main_reset_core,
      main_key_num_o          => main_key_num,
      main_key_pressed_n_o    => main_key_pressed_n,
      main_power_led_i        => main_power_led,
      main_power_led_col_i    => main_power_led_col,
      main_drive_led_i        => main_drive_led,
      main_drive_led_col_i    => main_drive_led_col,
      main_osm_control_m_o    => main_osm_control_m,
      main_qnice_gp_reg_o     => main_qnice_gp_reg,
      -- TEMPORARY: audio muted during bring-up (democore's constant test tone
      -- is annoying); restore main_audio_l/r here when done
      main_audio_l_i          => (others => '0'),
      main_audio_r_i          => (others => '0'),
      video_clk_i             => video_clk,
      video_rst_i             => video_rst,
      video_ce_i              => video_ce,
      video_ce_ovl_i          => video_ce_ovl,
      video_red_i             => video_red,
      video_green_i           => video_green,
      video_blue_i            => video_blue,
      video_vs_i              => video_vs,
      video_hs_i              => video_hs,
      video_hblank_i          => video_hblank,
      video_vblank_i          => video_vblank,
      main_joy1_up_n_o        => main_joy1_up_n_in,
      main_joy1_down_n_o      => main_joy1_down_n_in,
      main_joy1_left_n_o      => main_joy1_left_n_in,
      main_joy1_right_n_o     => main_joy1_right_n_in,
      main_joy1_fire_n_o      => main_joy1_fire_n_in,
      main_joy1_up_n_i        => main_joy1_up_n_out,
      main_joy1_down_n_i      => main_joy1_down_n_out,
      main_joy1_left_n_i      => main_joy1_left_n_out,
      main_joy1_right_n_i     => main_joy1_right_n_out,
      main_joy1_fire_n_i      => main_joy1_fire_n_out,
      main_joy2_up_n_o        => main_joy2_up_n_in,
      main_joy2_down_n_o      => main_joy2_down_n_in,
      main_joy2_left_n_o      => main_joy2_left_n_in,
      main_joy2_right_n_o     => main_joy2_right_n_in,
      main_joy2_fire_n_o      => main_joy2_fire_n_in,
      main_joy2_up_n_i        => main_joy2_up_n_out,
      main_joy2_down_n_i      => main_joy2_down_n_out,
      main_joy2_left_n_i      => main_joy2_left_n_out,
      main_joy2_right_n_i     => main_joy2_right_n_out,
      main_joy2_fire_n_i      => main_joy2_fire_n_out,
      main_pot1_x_o           => main_pot1_x,
      main_pot1_y_o           => main_pot1_y,
      main_pot2_x_o           => main_pot2_x,
      main_pot2_y_o           => main_pot2_y,
      main_rtc_o              => main_rtc,

      -- Provide external memory to core (in HyperRAM clock domain)
      hr_clk_o                => hr_clk,
      hr_rst_o                => hr_rst,
      hr_core_write_i         => hr_core_write,
      hr_core_read_i          => hr_core_read,
      hr_core_address_i       => hr_core_address,
      hr_core_writedata_i     => hr_core_writedata,
      hr_core_byteenable_i    => hr_core_byteenable,
      hr_core_burstcount_i    => hr_core_burstcount,
      hr_core_readdata_o      => hr_core_readdata,
      hr_core_readdatavalid_o => hr_core_readdatavalid,
      hr_core_waitrequest_o   => hr_core_waitrequest,
      hr_high_o               => hr_high,
      hr_low_o                => hr_low,

      -- Audio (no DAC on the Wukong; sound is embedded in HDMI)
      audio_clk_o             => open,
      audio_reset_o           => open,
      audio_left_o            => open,
      audio_right_o           => open,

      -- Connect to QNICE
      qnice_dvi_i             => qnice_dvi,
      qnice_video_mode_i      => qnice_video_mode,
      qnice_scandoubler_i     => qnice_scandoubler,
      qnice_csync_i           => qnice_csync,
      qnice_audio_mute_i      => qnice_audio_mute,
      qnice_audio_filter_i    => qnice_audio_filter,
      qnice_zoom_crop_i       => qnice_zoom_crop,
      qnice_osm_cfg_scaling_i => qnice_osm_cfg_scaling,
      qnice_retro15kHz_i      => qnice_retro15kHz,
      qnice_ascal_mode_i      => qnice_ascal_mode,
      qnice_ascal_polyphase_i => qnice_ascal_polyphase,
      qnice_ascal_triplebuf_i => qnice_ascal_triplebuf,
      qnice_flip_joyports_i   => qnice_flip_joyports,
      qnice_osm_control_m_o   => qnice_osm_control_m,
      qnice_gp_reg_o          => qnice_gp_reg,
      qnice_ramrom_dev_o      => qnice_ramrom_dev,
      qnice_ramrom_addr_o     => qnice_ramrom_addr,
      qnice_ramrom_data_out_o => qnice_ramrom_data_out,
      qnice_ramrom_data_in_i  => qnice_ramrom_data_in,
      qnice_ramrom_ce_o       => qnice_ramrom_ce,
      qnice_ramrom_we_o       => qnice_ramrom_we,
      qnice_ramrom_wait_i     => qnice_ramrom_wait
   ); -- i_framework


   ---------------------------------------------------------------------------------------------------------------
   -- MEGA65 Core including the MiSTer core: Multiple clock domains
   ---------------------------------------------------------------------------------------------------------------

   CORE : entity work.MEGA65_Core
      generic map (
         G_BOARD => "WUKONG"
      )
      port map (
         clk_i                   => clk_100,

         -- Share clock and reset with the framework
         main_clk_o              => main_clk,
         main_rst_o              => main_rst,

         --------------------------------------------------------------------------------------------------------
         -- QNICE Clock Domain
         --------------------------------------------------------------------------------------------------------

         qnice_clk_i             => qnice_clk,
         qnice_rst_i             => qnice_rst,

         -- Video and audio mode control
         qnice_dvi_o             => qnice_dvi,
         qnice_video_mode_o      => qnice_video_mode,
         qnice_scandoubler_o     => qnice_scandoubler,
         qnice_csync_o           => qnice_csync,
         qnice_audio_mute_o      => qnice_audio_mute,
         qnice_audio_filter_o    => qnice_audio_filter,
         qnice_zoom_crop_o       => qnice_zoom_crop,
         qnice_ascal_mode_o      => qnice_ascal_mode,
         qnice_ascal_polyphase_o => qnice_ascal_polyphase,
         qnice_ascal_triplebuf_o => qnice_ascal_triplebuf,
         qnice_retro15kHz_o      => qnice_retro15kHz,
         qnice_osm_cfg_scaling_o => qnice_osm_cfg_scaling,

         -- Flip joystick ports
         qnice_flip_joyports_o   => qnice_flip_joyports,

         -- On-Screen-Menu selections (in QNICE clock domain)
         qnice_osm_control_i     => qnice_osm_control_m,

         -- QNICE general purpose register
         qnice_gp_reg_i          => qnice_gp_reg,

         -- Core-specific devices
         qnice_dev_id_i          => qnice_ramrom_dev,
         qnice_dev_addr_i        => qnice_ramrom_addr,
         qnice_dev_data_i        => qnice_ramrom_data_out,
         qnice_dev_data_o        => qnice_ramrom_data_in,
         qnice_dev_ce_i          => qnice_ramrom_ce,
         qnice_dev_we_i          => qnice_ramrom_we,
         qnice_dev_wait_o        => qnice_ramrom_wait,

         --------------------------------------------------------------------------------------------------------
         -- Core Clock Domain
         --------------------------------------------------------------------------------------------------------

         main_reset_m2m_i        => main_reset_m2m  or main_qnice_reset or main_rst,
         main_reset_core_i       => main_reset_core or main_qnice_reset,
         main_pause_core_i       => main_qnice_pause,

         main_osm_control_i      => main_osm_control_m,
         main_qnice_gp_reg_i     => main_qnice_gp_reg,

         -- Video output
         video_clk_o             => video_clk,
         video_rst_o             => video_rst,
         video_ce_o              => video_ce,
         video_ce_ovl_o          => video_ce_ovl,
         video_red_o             => video_red,
         video_green_o           => video_green,
         video_blue_o            => video_blue,
         video_vs_o              => video_vs,
         video_hs_o              => video_hs,
         video_hblank_o          => video_hblank,
         video_vblank_o          => video_vblank,

         -- Audio output (Signed PCM)
         main_audio_left_o       => main_audio_l,
         main_audio_right_o      => main_audio_r,

         -- M2M Keyboard interface
         main_kb_key_num_i       => main_key_num,
         main_kb_key_pressed_n_i => main_key_pressed_n,
         main_power_led_o        => main_power_led,
         main_power_led_col_o    => main_power_led_col,
         main_drive_led_o        => main_drive_led,
         main_drive_led_col_o    => main_drive_led_col,

         -- Joysticks input
         main_joy_1_up_n_i       => main_joy1_up_n_in,
         main_joy_1_down_n_i     => main_joy1_down_n_in,
         main_joy_1_left_n_i     => main_joy1_left_n_in,
         main_joy_1_right_n_i    => main_joy1_right_n_in,
         main_joy_1_fire_n_i     => main_joy1_fire_n_in,
         main_joy_1_up_n_o       => main_joy1_up_n_out,
         main_joy_1_down_n_o     => main_joy1_down_n_out,
         main_joy_1_left_n_o     => main_joy1_left_n_out,
         main_joy_1_right_n_o    => main_joy1_right_n_out,
         main_joy_1_fire_n_o     => main_joy1_fire_n_out,

         main_joy_2_up_n_i       => main_joy2_up_n_in,
         main_joy_2_down_n_i     => main_joy2_down_n_in,
         main_joy_2_left_n_i     => main_joy2_left_n_in,
         main_joy_2_right_n_i    => main_joy2_right_n_in,
         main_joy_2_fire_n_i     => main_joy2_fire_n_in,
         main_joy_2_up_n_o       => main_joy2_up_n_out,
         main_joy_2_down_n_o     => main_joy2_down_n_out,
         main_joy_2_left_n_o     => main_joy2_left_n_out,
         main_joy_2_right_n_o    => main_joy2_right_n_out,
         main_joy_2_fire_n_o     => main_joy2_fire_n_out,

         main_pot1_x_i           => main_pot1_x,
         main_pot1_y_i           => main_pot1_y,
         main_pot2_x_i           => main_pot2_x,
         main_pot2_y_i           => main_pot2_y,
         main_rtc_i              => main_rtc,

         --------------------------------------------------------------------------------------------------------
         -- Provide support for external memory (Avalon Memory Map)
         --------------------------------------------------------------------------------------------------------

         hr_clk_i                => hr_clk,
         hr_rst_i                => hr_rst,
         hr_core_write_o         => hr_core_write,
         hr_core_read_o          => hr_core_read,
         hr_core_address_o       => hr_core_address,
         hr_core_writedata_o     => hr_core_writedata,
         hr_core_byteenable_o    => hr_core_byteenable,
         hr_core_burstcount_o    => hr_core_burstcount,
         hr_core_readdata_i      => hr_core_readdata,
         hr_core_readdatavalid_i => hr_core_readdatavalid,
         hr_core_waitrequest_i   => hr_core_waitrequest,
         hr_high_i               => hr_high,
         hr_low_i                => hr_low,

         --------------------------------------------------------------------
         -- Ports that have no counterpart on the Wukong: IEC, Expansion Port
         --------------------------------------------------------------------

         iec_reset_n_o           => open,
         iec_atn_n_o             => open,
         iec_clk_en_o            => open,
         iec_clk_n_i             => '1',
         iec_clk_n_o             => open,
         iec_data_en_o           => open,
         iec_data_n_i            => '1',
         iec_data_n_o            => open,
         iec_srq_en_o            => open,
         iec_srq_n_i             => '1',
         iec_srq_n_o             => open,

         cart_en_o               => open,
         cart_phi2_o             => open,
         cart_dotclock_o         => open,
         cart_dma_i              => '1',
         cart_reset_oe_o         => open,
         cart_reset_i            => '1',
         cart_reset_o            => open,
         cart_game_oe_o          => open,
         cart_game_i             => '1',
         cart_game_o             => open,
         cart_exrom_oe_o         => open,
         cart_exrom_i            => '1',
         cart_exrom_o            => open,
         cart_nmi_oe_o           => open,
         cart_nmi_i              => '1',
         cart_nmi_o              => open,
         cart_irq_oe_o           => open,
         cart_irq_i              => '1',
         cart_irq_o              => open,
         cart_roml_oe_o          => open,
         cart_roml_i             => '1',
         cart_roml_o             => open,
         cart_romh_oe_o          => open,
         cart_romh_i             => '1',
         cart_romh_o             => open,
         cart_ctrl_oe_o          => open,
         cart_ba_i               => '1',
         cart_rw_i               => '1',
         cart_io1_i              => '1',
         cart_io2_i              => '1',
         cart_ba_o               => open,
         cart_rw_o               => open,
         cart_io1_o              => open,
         cart_io2_o              => open,
         cart_data_oe_o          => open,
         cart_d_i                => (others => '1'),
         cart_d_o                => open,
         cart_addr_oe_o          => open,
         cart_a_i                => (others => '1'),
         cart_a_o                => open
      ); -- CORE

end architecture synthesis;
