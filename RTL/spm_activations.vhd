library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spm_activations is
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        sensor_data_in  : in  std_logic_vector(31 downto 0);
        sensor_valid    : in  std_logic;
        act0_out        : out std_logic_vector(7 downto 0);
        act1_out        : out std_logic_vector(7 downto 0);
        act2_out        : out std_logic_vector(7 downto 0);
        act3_out        : out std_logic_vector(7 downto 0)
    );
end entity spm_activations;

architecture Behavioral of spm_activations is
    signal reg_act0 : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_act1 : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_act2 : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_act3 : std_logic_vector(7 downto 0) := (others => '0');
begin
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            reg_act0 <= (others => '0');
            reg_act1 <= (others => '0');
            reg_act2 <= (others => '0');
            reg_act3 <= (others => '0');
        elsif rising_edge(clk) then
            if sensor_valid = '1' then
                reg_act0 <= sensor_data_in(31 downto 24);
                reg_act1 <= sensor_data_in(23 downto 16);
                reg_act2 <= sensor_data_in(15 downto 8);
                reg_act3 <= sensor_data_in(7 downto 0);
            end if;
        end if;
    end process;

    act0_out <= reg_act0;
    act1_out <= reg_act1;
    act2_out <= reg_act2;
    act3_out <= reg_act3;
end architecture Behavioral;