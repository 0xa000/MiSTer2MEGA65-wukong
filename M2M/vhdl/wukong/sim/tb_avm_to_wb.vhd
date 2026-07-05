-------------------------------------------------------------------------------------------------------------
-- Self-checking testbench for avm_to_wb (Avalon-MM to pipelined Wishbone bridge)
--
-- The Wishbone slave model mimics UberDDR3's bus behavior: pseudo-random
-- stalls, in-order acks after a pseudo-random pipeline latency, 128-bit data.
-- Scenarios: single write, burst write, single read, burst read, and a read
-- issued back-to-back after writes (verifies the write-ack drain interlock).
--
-- Run:
--   xvhdl --2008 ../avm_to_wb.vhd tb_avm_to_wb.vhd
--   xelab --debug typical tb_avm_to_wb -s tb_avm_to_wb_sim
--   xsim tb_avm_to_wb_sim -runall
--
-- Wukong port done by 0xa000 in 2026 and licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_avm_to_wb is
end entity tb_avm_to_wb;

architecture sim of tb_avm_to_wb is

   constant C_AVM_ADDRESS_SIZE : integer := 29;
   constant C_WB_ADDRESS_SIZE  : integer := 24;
   constant C_DATA_SIZE        : integer := 128;

   signal clk : std_logic := '0';
   signal rst : std_logic := '1';

   -- Avalon
   signal avm_write         : std_logic := '0';
   signal avm_read          : std_logic := '0';
   signal avm_address       : std_logic_vector(C_AVM_ADDRESS_SIZE - 1 downto 0) := (others => '0');
   signal avm_writedata     : std_logic_vector(C_DATA_SIZE - 1 downto 0) := (others => '0');
   signal avm_byteenable    : std_logic_vector(C_DATA_SIZE / 8 - 1 downto 0) := (others => '1');
   signal avm_burstcount    : std_logic_vector(7 downto 0) := x"01";
   signal avm_readdata      : std_logic_vector(C_DATA_SIZE - 1 downto 0);
   signal avm_readdatavalid : std_logic;
   signal avm_waitrequest   : std_logic;

   -- Wishbone
   signal wb_cyc   : std_logic;
   signal wb_stb   : std_logic;
   signal wb_we    : std_logic;
   signal wb_addr  : std_logic_vector(C_WB_ADDRESS_SIZE - 1 downto 0);
   signal wb_data  : std_logic_vector(C_DATA_SIZE - 1 downto 0);
   signal wb_sel   : std_logic_vector(C_DATA_SIZE / 8 - 1 downto 0);
   signal wb_stall : std_logic;
   signal wb_ack   : std_logic := '0';
   signal wb_rdata : std_logic_vector(C_DATA_SIZE - 1 downto 0) := (others => '0');

   signal test_done : boolean := false;
   signal slave_errors : natural := 0;
   signal stim_errors  : natural := 0;

   -- deterministic "memory": data = f(word address)
   function f_data (addr : natural) return std_logic_vector is
      variable v : unsigned(C_DATA_SIZE - 1 downto 0);
   begin
      v := (others => '0');
      v(23 downto 0)   := to_unsigned(addr, 24);
      v(55 downto 32)  := to_unsigned(addr, 24) xor x"A5A5A5";
      v(127 downto 96) := x"DEADBEEF";
      return std_logic_vector(v);
   end function f_data;

begin

   clk <= not clk after 5 ns when not test_done else '0';
   rst <= '0' after 42 ns;

   i_dut : entity work.avm_to_wb
      generic map (
         G_AVM_ADDRESS_SIZE => C_AVM_ADDRESS_SIZE,
         G_WB_ADDRESS_SIZE  => C_WB_ADDRESS_SIZE,
         G_DATA_SIZE        => C_DATA_SIZE
      )
      port map (
         clk_i                 => clk,
         rst_i                 => rst,
         s_avm_write_i         => avm_write,
         s_avm_read_i          => avm_read,
         s_avm_address_i       => avm_address,
         s_avm_writedata_i     => avm_writedata,
         s_avm_byteenable_i    => avm_byteenable,
         s_avm_burstcount_i    => avm_burstcount,
         s_avm_readdata_o      => avm_readdata,
         s_avm_readdatavalid_o => avm_readdatavalid,
         s_avm_waitrequest_o   => avm_waitrequest,
         wb_cyc_o              => wb_cyc,
         wb_stb_o              => wb_stb,
         wb_we_o               => wb_we,
         wb_addr_o             => wb_addr,
         wb_data_o             => wb_data,
         wb_sel_o              => wb_sel,
         wb_stall_i            => wb_stall,
         wb_ack_i              => wb_ack,
         wb_data_i             => wb_rdata
      ); -- i_dut

   ---------------------------------------------------------------------------
   -- Wishbone slave model: pseudo-random stalls, in-order acks with
   -- pseudo-random latency, checks written data against f_data
   ---------------------------------------------------------------------------
   p_wb_slave : process (clk)
      type t_req is record
         we    : std_logic;
         addr  : natural;
         delay : natural;
      end record;
      type t_req_queue is array (0 to 63) of t_req;
      variable q       : t_req_queue;
      variable q_wr    : natural := 0;
      variable q_rd    : natural := 0;
      variable lfsr    : unsigned(15 downto 0) := x"ACE1";
      variable pending : integer := 0;
   begin
      if rising_edge(clk) then
         -- advance pseudo-random generator
         lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

         -- accept request
         if wb_cyc = '1' and wb_stb = '1' and wb_stall = '0' then
            q(q_wr).we    := wb_we;
            q(q_wr).addr  := to_integer(unsigned(wb_addr));
            q(q_wr).delay := 2 + to_integer(lfsr(2 downto 0));  -- 2..9 cycles
            if wb_we = '1' then
               assert wb_data = f_data(to_integer(unsigned(wb_addr)))
                  report "WB slave: write data mismatch at addr " &
                         integer'image(to_integer(unsigned(wb_addr)))
                  severity error;
               if wb_data /= f_data(to_integer(unsigned(wb_addr))) then
                  slave_errors <= slave_errors + 1;
               end if;
            end if;
            q_wr    := (q_wr + 1) mod 64;
            pending := pending + 1;
         end if;

         -- age the queue and ack the oldest request when its delay expired
         wb_ack <= '0';
         if pending > 0 then
            if q(q_rd).delay > 0 then
               q(q_rd).delay := q(q_rd).delay - 1;
            else
               wb_ack <= '1';
               if q(q_rd).we = '0' then
                  wb_rdata <= f_data(q(q_rd).addr);
               end if;
               q_rd    := (q_rd + 1) mod 64;
               pending := pending - 1;
            end if;
         end if;
      end if;
   end process p_wb_slave;

   -- pseudo-random stall pattern, changes every cycle
   p_stall : process (clk)
      variable lfsr2 : unsigned(15 downto 0) := x"BEEF";
   begin
      if rising_edge(clk) then
         lfsr2 := lfsr2(14 downto 0) & (lfsr2(15) xor lfsr2(13) xor lfsr2(12) xor lfsr2(10));
         wb_stall <= lfsr2(0) and lfsr2(3);   -- stalls ~25% of cycles
      end if;
   end process p_stall;

   ---------------------------------------------------------------------------
   -- Stimulus and checking
   ---------------------------------------------------------------------------
   p_stimulus : process
      variable v_rx_count : natural;

      procedure avm_write_burst (addr : natural; count : natural) is
         variable beat : natural := 0;
      begin
         avm_address    <= std_logic_vector(to_unsigned(addr, C_AVM_ADDRESS_SIZE));
         avm_burstcount <= std_logic_vector(to_unsigned(count, 8));
         while beat < count loop
            avm_write     <= '1';
            avm_writedata <= f_data(addr + beat);
            wait until rising_edge(clk);
            if avm_waitrequest = '0' then
               beat := beat + 1;
            end if;
         end loop;
         avm_write <= '0';
      end procedure avm_write_burst;

      procedure avm_read_burst (addr : natural; count : natural) is
         variable got : natural := 0;
      begin
         avm_address    <= std_logic_vector(to_unsigned(addr, C_AVM_ADDRESS_SIZE));
         avm_burstcount <= std_logic_vector(to_unsigned(count, 8));
         avm_read       <= '1';
         loop
            wait until rising_edge(clk);
            exit when avm_waitrequest = '0';
         end loop;
         avm_read <= '0';
         -- collect read data
         while got < count loop
            wait until rising_edge(clk);
            if avm_readdatavalid = '1' then
               assert avm_readdata = f_data(addr + got)
                  report "Avalon read data mismatch at " & integer'image(addr + got)
                  severity error;
               if avm_readdata /= f_data(addr + got) then
                  stim_errors <= stim_errors + 1;
               end if;
               got := got + 1;
            end if;
         end loop;
      end procedure avm_read_burst;

   begin
      wait until rst = '0';
      wait until rising_edge(clk);

      -- 1: single write
      avm_write_burst(16#000010#, 1);
      -- 2: burst write
      avm_write_burst(16#000100#, 8);
      -- 3: read immediately after writes (tests the pending-write interlock)
      avm_read_burst(16#000100#, 8);
      -- 4: single read
      avm_read_burst(16#000010#, 1);
      -- 5: interleave: burst write directly followed by single write and burst read
      avm_write_burst(16#000200#, 4);
      avm_write_burst(16#000204#, 1);
      avm_read_burst(16#000200#, 5);
      -- 6: long burst (crosses several ack latencies)
      avm_write_burst(16#000300#, 64);
      avm_read_burst(16#000300#, 64);

      wait for 500 ns;

      if slave_errors + stim_errors = 0 then
         report "TB PASSED: all scenarios OK" severity note;
      else
         report "TB FAILED: " & integer'image(slave_errors + stim_errors) & " errors" severity error;
      end if;
      test_done <= true;
      wait;
   end process p_stimulus;

end architecture sim;
