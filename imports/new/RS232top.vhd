
library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   
entity RS232top is

  port (
    Reset     : in  std_logic;   -- Low-level asynchronous reset
    Clk       : in  std_logic;   -- System clock (100MHz), rising edge 
	
    Data_in   : in  std_logic_vector(8 downto 0);  -- Parallel TX byte 
    TX_Send   : in  std_logic;   -- Handshake signal from guest, active low 
    Ack_in    : out std_logic;   -- Data ack, low when it has been stored
    TX_RDY    : out std_logic;   -- System ready to transmit
    TD        : out std_logic;   -- RS232 Transmission line
	
    RD        : in  std_logic;   -- RS232 Reception line
    Data_out  : out std_logic_vector(8 downto 0);  -- Parallel RX byte
    Data_read : in  std_logic;   -- Send RX data to guest 
    Full      : out std_logic;   -- Internal RX memory full 
    Empty     : out std_logic;  -- Internal RX memory empty
    
    PAR_ERROR : out std_logic;
    FRAME_ERROR : out std_logic;
    
    baudrate  : in std_logic_vector(31 downto 0); -- configurable to 36 standard bps
    stop_bit  : in std_logic_vector(1 downto 0);  -- 1, 1.5 or 2 stop bits
    parity    : in std_logic_vector(2 downto 0);  -- 0→Even, 1→Odd, 2→Mark(=1), 3→Space(=0), 4→parity disabled
    bit_order : in std_logic;                     -- 0→LSB-first (default), 1→MSB-first
    data_bits  : in std_logic_vector(1 downto 0)); -- 0→5b, 1→6b, 2→7b, 3→8b, 4→9b

end RS232top;

architecture RTL of RS232top is
 
 ------------------------------------------------------------------------
  -- Components for Transmitter Block
  ------------------------------------------------------------------------

  component RS232_TX
    Port (
        Clk   : in  STD_LOGIC;
        Reset : in  STD_LOGIC;
        Start : in  STD_LOGIC;
        Data  : in  STD_LOGIC_VECTOR (8 downto 0);
        baudrate  : in std_logic_vector(31 downto 0); -- configurable to 36 standard bps
        stop_bit  : in std_logic_vector(2 downto 0);  -- 1 (010), 1.5(011) or 2(100) stop bits ( 2, 3 or 4 half ticks)
        parity    : in std_logic_vector(2 downto 0);  -- 0→Even, 1→Odd, 2→Mark(=1), 3→Space(=0), 4→parity disabled
        bit_order : in std_logic;                     -- 0→LSB-first (default), 1→MSB-first
        data_bits  : in std_logic_vector(2 downto 0); -- 0→5b, 1→6b, 2→7b, 3→8b, 4→9b                
        EOT   : out STD_LOGIC;
        TX    : out STD_LOGIC
    );
  end component;

  ------------------------------------------------------------------------
  -- Components for Receiver Block
  ------------------------------------------------------------------------

  component ShiftRegister
    port (
      Reset  : in  std_logic;
      Clk    : in  std_logic;
      Enable : in  std_logic;
      D      : in  std_logic;
      Q      : out std_logic_vector(7 downto 0));
  end component;

  component RS232_RX
    port (
      Clk       : in  std_logic;
      Reset     : in  std_logic;
      LineRD_in : in  std_logic;
      Valid_out : out std_logic;
      Code_out  : out std_logic;
      Store_out : out std_logic);
  end component;

  component fifo_generator_0
    port (
      clk   : IN  std_logic;
      srst  : IN  std_logic;
      din   : IN  std_logic_VECTOR(7 downto 0);
      wr_en : IN  std_logic;
      rd_en : IN  std_logic;
      dout  : OUT std_logic_VECTOR(7 downto 0);
      full  : OUT std_logic;
      empty : OUT std_logic);
  end component;
  


  ------------------------------------------------------------------------
  -- Internal Signals
  ------------------------------------------------------------------------

  signal Data_FF    : std_logic_vector(7 downto 0);
  signal StartTX    : std_logic;  -- start signal for transmitter
  signal LineRD_in  : std_logic;  -- internal RX line
  signal Valid_out  : std_logic;  -- valid bit at the receiver
  signal Code_out   : std_logic;  -- bit at the receiver output
  signal sinit      : std_logic;  -- fifo reset
  signal Fifo_in    : std_logic_vector(7 downto 0);
  signal Fifo_write : std_logic;
  signal TX_RDY_i   : std_logic;

begin  -- RTL

  Transmitter: RS232_TX
    port map (
      Clk   => Clk,
      Reset => Reset,
      Start => StartTX,
      Data  => Data_FF,
      baudrate  => baudrate,
      stop_bit  => stop_bit,
      parity    => parity,
      bit_order => bit_order,
      data_bits  => data_bits,      
      EOT   => TX_RDY_i,
      TX    => TD);

  Receiver: RS232_RX
    port map (
      Clk       => Clk,
      Reset     => Reset,
      LineRD_in => LineRD_in,
      Valid_out => Valid_out,
      Code_out  => Code_out,
      Store_out => Fifo_write);

  Shift: ShiftRegister
    port map (
      Reset  => Reset,
      Clk    => Clk,
      Enable => Valid_Out,
      D      => Code_Out,
      Q      => Fifo_in);

  sinit <= not reset;
  
  Internal_memory: fifo_generator_0
    port map (
      clk   => clk,
      srst  => sinit,
      din   => Fifo_in,
      wr_en => Fifo_write,
      rd_en => Data_read,
      dout  => Data_out,
      full  => Full,
      empty => Empty);


  -- purpose: Clocking process for input protocol
  Clocking : process (Clk, Reset)
  begin
    if Reset = '0' then  -- asynchronous reset (active low)
      Data_FF   <= (others => '0');
      LineRD_in <= '1';
      Ack_in    <= '1';
    elsif rising_edge(Clk) then  -- rising edge of the clock
      LineRD_in <= RD;
      if TX_Send = '0' and TX_RDY_i = '1' then
        Data_FF <= Data_in;
        Ack_in  <= '0';
        StartTX <= '1';
      else
        Ack_in  <= '1';
        StartTX <= '0';
      end if;
    end if;
  end process Clocking;
  
 -- Logic : process (Valid_D, TX_RDY_i)
 -- begin
 --   Ack_in <= '1';
 --   if Valid_D = '0' and TX_RDY_i = '1' then
  --      Ack_in  <= '0';
   -- end if;
  --end process Logic;

  TX_RDY <= TX_RDY_i;

end RTL;

