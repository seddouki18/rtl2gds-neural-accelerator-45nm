library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package adas_types_pkg is
    type wgt_bank_t is array (0 to 272) of std_logic_vector(7 downto 0);
end package adas_types_pkg;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.adas_types_pkg.all;

entity mem_controller is
    port (
        clk          : in  std_logic;
        rst_n        : in  std_logic;
        wr_en        : in  std_logic;
        wr_bank      : in  std_logic;
        wr_addr      : in  std_logic_vector(8 downto 0);
        wr_data      : in  std_logic_vector(7 downto 0);
        bank_select  : in  std_logic;
        dma_done     : in  std_logic;
        ready_A      : out std_logic;
        ready_B      : out std_logic;
        rd_weights   : out wgt_bank_t
    );
end entity mem_controller;

architecture Behavioral of mem_controller is
    signal ram_bank_A : wgt_bank_t := (others => (others => '0'));
    signal ram_bank_B : wgt_bank_t := (others => (others => '0'));
    signal s_ready_A  : std_logic := '0';
    signal s_ready_B  : std_logic := '0';
begin

    process(clk, rst_n)
        variable addr_int : integer;
    begin
        if rst_n = '0' then
            ram_bank_A <= (others => (others => '0'));
            ram_bank_B <= (others => (others => '0'));
            s_ready_A  <= '0';
            s_ready_B  <= '0';
        elsif rising_edge(clk) then
            if wr_en = '1' then
                addr_int := to_integer(unsigned(wr_addr));
                if addr_int <= 272 then
                    if wr_bank = '0' then
                        if addr_int = 0 then
                            ram_bank_A    <= (0 => wr_data, others => (others => '0'));
                            s_ready_A     <= '0';
                        else
                            ram_bank_A(addr_int) <= wr_data;
                        end if;
                    else
                        if addr_int = 0 then
                            ram_bank_B    <= (0 => wr_data, others => (others => '0'));
                            s_ready_B     <= '0';
                        else
                            ram_bank_B(addr_int) <= wr_data;
                        end if;
                    end if;
                end if;
            end if;

            if dma_done = '1' then
                if wr_bank = '0' then
                    s_ready_A <= '1';
                else
                    s_ready_B <= '1';
                end if;
            end if;
        end if;
    end process;

    ready_A    <= s_ready_A;
    ready_B    <= s_ready_B;
    rd_weights <= ram_bank_A when bank_select = '0' else ram_bank_B;

end architecture Behavioral;