----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/19/2025 12:37:16 PM
-- Design Name: 
-- Module Name: SERIAL_INTERFACE - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells out this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity SERIAL_INTERFACE is
  Port (
    -- PS ack_in, TX_RDY, Data_out, FULL, EMPTY, PAR ERROR, FRAME_ERROR
    PS_out : out std_logic_vector(13 downto 0);
    -- PS RX
    PS_RX_DataRead_ErrorOk  : in std_logic_vector(1 downto 0);
    -- PS TX
    PS_TX_DataIn_Send : in std_logic_vector(9 downto 0);
    -- PS CONFIG
    PS_SERIAL_CONFIG : in std_logic_vector(31 downto 0);    
    -- PL TX	
    Data_in   : out  std_logic_vector(8 downto 0);  -- Parallel TX byte 
    TX_Send   : out  std_logic;   -- Handshake signal from guest, active low 
    TX_RDY    : in std_logic;   -- System ready to transmit
	-- PL RX
    Data_out  : in std_logic_vector(8 downto 0);  -- Parallel RX byte
    Data_read : out  std_logic;   -- Send RX data to guest 
    Full      : in std_logic;   -- Internal RX memory full 
    Empty     : in std_logic;  -- Internal RX memory empty
    -- PL RX ERROR
    PAR_ERROR : in std_logic;
    FRAME_ERROR : in std_logic;
    ERROR_OK  : out std_logic;
    -- PL CONFIG
    baudrate  : out std_logic_vector(21 downto 0); -- configurable to 36 standard bps
    stop_bit  : out std_logic_vector(2 downto 0);  -- 1, 1.5 or 2 stop bits
    parity    : out std_logic_vector(2 downto 0);  -- 0→Even, 1→Odd, 2→Mark(=1), 3→Space(=0), 4→parity disabled
    bit_order : out std_logic;                     -- 0→LSB-first (default), 1→MSB-first
    data_bits  : out std_logic_vector(2 downto 0)); -- 0→5b, 1→6b, 2→7b, 3→8b, 4→9b

end SERIAL_INTERFACE;

architecture Behavioral of SERIAL_INTERFACE is

begin
    PS_out <= TX_RDY & FRAME_ERROR & PAR_ERROR & FULL & EMPTY & Data_out;
    --PS_TX_out_ack_txrdy  <= Ack_in & TX_RDY;
    -- PL TX	
    Data_in   <= PS_TX_DataIn_Send(8 downto 0);
    TX_Send   <= PS_TX_DataIn_Send(9);
    -- PS RX
    --PS_RX_out_data_out_full_empty_error <= FRAME_ERROR & PAR_ERROR & FULL & EMPTY & Data_out;
	-- PL RX
    Data_read <= PS_RX_DataRead_ErrorOk(0);
    ERROR_OK  <= PS_RX_DataRead_ErrorOk(1);
    -- PL CONFIG
    -- GPIO0
    baudrate  <= PS_SERIAL_CONFIG(21 DOWNTO 0);
    stop_bit  <= PS_SERIAL_CONFIG(24 downto 22);
    parity    <= PS_SERIAL_CONFIG(27 downto 25);
    bit_order <= PS_SERIAL_CONFIG(31);
    data_bits  <= PS_SERIAL_CONFIG(30 downto 28);

end Behavioral;
