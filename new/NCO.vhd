----------------------------------------------------------------------------------
-- NCO con ROM de baudios (Fclk = 100 MHz, N = 32)
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity NCO is
  generic(
    N : integer := 32
  );
  port(
    clk       : in  std_logic;
    rst       : in  std_logic;                 -- activo a '0'
    en        : in  std_logic;
    half_mode : in  std_logic;                 -- '0' -> inc normal, '1' -> inc_half (2x baud)
    baudrate  : in  std_logic_vector(21 downto 0); -- valor decimal del baud
    tick      : out std_logic
  );
end NCO;

architecture Behavioral of NCO is
  -- Acumulador y suma
  signal phase_reg, phase_next : unsigned(N-1 downto 0);
  signal sum                   : unsigned(N downto 0);

  -- Señales de ROM y selección
  signal inc_rom, inc_half_rom : unsigned(N-1 downto 0);
  signal inc_i                 : unsigned(N-1 downto 0);

  -- Tick registrado
  signal tick_reg, tick_next   : std_logic;
begin
  ----------------------------------------------------------------------------
  -- ROM de baudios -> inc / inc_half (Fclk=100MHz, N=32)
  ----------------------------------------------------------------------------
  rom_proc : process(baudrate)
    variable b : integer;
  begin
    b := to_integer(unsigned(baudrate));
    inc_rom      <= (others => '0');
    inc_half_rom <= (others => '0');

    case b is
      when 110      => inc_rom <= to_unsigned(4724, 32);       inc_half_rom <= to_unsigned(9449, 32);
      when 300      => inc_rom <= to_unsigned(12885, 32);      inc_half_rom <= to_unsigned(25770, 32);
      when 600      => inc_rom <= to_unsigned(25770, 32);      inc_half_rom <= to_unsigned(51540, 32);
      when 1200     => inc_rom <= to_unsigned(51540, 32);      inc_half_rom <= to_unsigned(103079, 32);
      when 1800     => inc_rom <= to_unsigned(77309, 32);      inc_half_rom <= to_unsigned(154619, 32);
      when 2400     => inc_rom <= to_unsigned(103079, 32);     inc_half_rom <= to_unsigned(206158, 32);
      when 4800     => inc_rom <= to_unsigned(206158, 32);     inc_half_rom <= to_unsigned(412317, 32);
      when 7200     => inc_rom <= to_unsigned(309238, 32);     inc_half_rom <= to_unsigned(618475, 32);
      when 9600     => inc_rom <= to_unsigned(412317, 32);     inc_half_rom <= to_unsigned(824634, 32);
      when 14400    => inc_rom <= to_unsigned(618475, 32);     inc_half_rom <= to_unsigned(1236951, 32);
      when 19200    => inc_rom <= to_unsigned(824634, 32);     inc_half_rom <= to_unsigned(1649267, 32);
      when 28800    => inc_rom <= to_unsigned(1236951, 32);    inc_half_rom <= to_unsigned(2473901, 32);
      when 31250    => inc_rom <= to_unsigned(1342177, 32);    inc_half_rom <= to_unsigned(2684355, 32);
      when 38400    => inc_rom <= to_unsigned(1649267, 32);    inc_half_rom <= to_unsigned(3298535, 32);
      when 56000    => inc_rom <= to_unsigned(2405182, 32);    inc_half_rom <= to_unsigned(4810363, 32);
      when 57600    => inc_rom <= to_unsigned(2473901, 32);    inc_half_rom <= to_unsigned(4947802, 32);
      when 74400    => inc_rom <= to_unsigned(3195456, 32);    inc_half_rom <= to_unsigned(6390911, 32);
      when 74880    => inc_rom <= to_unsigned(3216897, 32);    inc_half_rom <= to_unsigned(6433794, 32);      
      when 115200   => inc_rom <= to_unsigned(4947802, 32);    inc_half_rom <= to_unsigned(9895605, 32);
      when 128000   => inc_rom <= to_unsigned(5497558, 32);    inc_half_rom <= to_unsigned(10995116, 32);
      when 153600   => inc_rom <= to_unsigned(6597070, 32);    inc_half_rom <= to_unsigned(13194140, 32);
      when 230400   => inc_rom <= to_unsigned(9895605, 32);    inc_half_rom <= to_unsigned(19791209, 32);
      when 250000   => inc_rom <= to_unsigned(10737418, 32);   inc_half_rom <= to_unsigned(21474836, 32);      
      when 256000   => inc_rom <= to_unsigned(10995116, 32);   inc_half_rom <= to_unsigned(21990233, 32);
      when 312500   => inc_rom <= to_unsigned(13421773, 32);   inc_half_rom <= to_unsigned(26843546, 32);
      when 460800   => inc_rom <= to_unsigned(19791209, 32);   inc_half_rom <= to_unsigned(39582419, 32);
      when 500000   => inc_rom <= to_unsigned(21474836, 32);   inc_half_rom <= to_unsigned(42949673, 32);
      when 576000   => inc_rom <= to_unsigned(24739012, 32);   inc_half_rom <= to_unsigned(49478023, 32);
      when 614400   => inc_rom <= to_unsigned(26388279, 32);   inc_half_rom <= to_unsigned(52776558, 32);
      when 750000   => inc_rom <= to_unsigned(32212255, 32);   inc_half_rom <= to_unsigned(64424509, 32);
      when 921600   => inc_rom <= to_unsigned(39582419, 32);   inc_half_rom <= to_unsigned(79164837, 32);
      when 1000000  => inc_rom <= to_unsigned(42949673, 32);   inc_half_rom <= to_unsigned(85899346, 32);
      when 1152000  => inc_rom <= to_unsigned(49478023, 32);   inc_half_rom <= to_unsigned(98956046, 32);
      when 1500000  => inc_rom <= to_unsigned(64424509, 32);  inc_half_rom <= to_unsigned(128849019, 32);
      when 1843200  => inc_rom <= to_unsigned(79164837, 32);   inc_half_rom <= to_unsigned(158329674, 32);
      when 2000000  => inc_rom <= to_unsigned(85899346, 32);   inc_half_rom <= to_unsigned(171798692, 32);
      when 2500000  => inc_rom <= to_unsigned(107374182, 32);  inc_half_rom <= to_unsigned(214748365, 32);
      when 3000000  => inc_rom <= to_unsigned(128849019, 32);  inc_half_rom <= to_unsigned(257698038, 32);
      when 3686400  => inc_rom <= to_unsigned(158329674, 32);  inc_half_rom <= to_unsigned(316659349, 32);
      when others   => null; -- si no coincide, quedan a cero
    end case;
  end process;

  -- Selección de incremento según half_mode
  inc_i <= inc_half_rom when (half_mode = '1') else inc_rom;

  ----------------------------------------------------------------------------
  -- Registro de fase y tick
  ----------------------------------------------------------------------------
  reg_proc : process(clk, rst)
  begin
    if rst = '0' then
      phase_reg <= (others => '0');
      tick_reg  <= '0';
    elsif rising_edge(clk) then
      if en = '1' then
        phase_reg <= phase_next;
        tick_reg  <= tick_next;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Lógica siguiente estado / salida
  ----------------------------------------------------------------------------
  sum        <= ('0' & phase_reg) + ('0' & inc_i);
  phase_next <= sum(N-1 downto 0);
  tick_next  <= sum(N);
  tick       <= tick_reg;

end Behavioral;
