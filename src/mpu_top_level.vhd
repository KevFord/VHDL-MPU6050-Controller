LIBRARY IEEE;
  USE IEEE.STD_LOGIC_1164.ALL;

ENTITY TOP_LEVEL IS
PORT (
  clk        : IN STD_LOGIC;
  rst_n      : IN STD_LOGIC;

  sda        : INOUT STD_LOGIC;

  scl        : OUT STD_LOGIC;
  led_o      : OUT STD_LOGIC_VECTOR(5 DOWNTO 0)
);
END ENTITY;


ARCHITECTURE RTL OF TOP_LEVEL IS

  COMPONENT i2c_master IS
  GENERIC (
    g_simulation           : BOOLEAN := true;
    g_reset_active_state   : STD_LOGIC := '0';
    g_fpga_clk_freq_mhz    : INTEGER RANGE 1 TO 200 := 27;
    g_desired_scl_freq_khz : INTEGER RANGE 1 TO 400 := 400
  );
  PORT (
  -- Clock and reset
    clk          : IN STD_LOGIC;
    rst_n        : IN STD_LOGIC;
  
  -- I2C signals
    scl          : OUT STD_LOGIC;
    sda          : INOUT STD_LOGIC;
  
  -- I2C control signals
  -- Inputs
    data_in      : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    dev_addr     : IN STD_LOGIC_VECTOR(7 DOWNTO 0); -- [7:1] address, [0] rw bit
    num_of_bytes : IN INTEGER RANGE 1 TO 2;
    input_valid  : IN STD_LOGIC;
  
  -- Outputs
    data_out     : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    data_valid   : OUT STD_LOGIC;
    error        : OUT STD_LOGIC
  );
  END COMPONENT;


COMPONENT mpu6050_ctrl IS
GENERIC (
  g_reset_active_state : STD_LOGIC := '0';
  g_fpga_clock_mhz     : INTEGER RANGE 1 TO 200 := 27
);
PORT (
-- Clock and reset
  clk          : IN STD_LOGIC;
  rst_n        : IN STD_LOGIC;

-- I2C control signals
-- Inputs
  data_out     : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
  data_valid   : IN STD_LOGIC;
  error        : IN STD_LOGIC;

-- Outputs
  data_in      : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
  dev_addr     : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- [7:1] address, [0] rw bit
  num_of_bytes : OUT INTEGER RANGE 1 TO 2;
  input_valid  : OUT STD_LOGIC;

-- The LEDs of the Tang Nano 9k board, used as status flags
  led_o        : OUT STD_LOGIC_VECTOR(5 DOWNTO 0)
);
END COMPONENT;

SIGNAL data_in      : STD_LOGIC_VECTOR(7 DOWNTO 0);
SIGNAL data_out     : STD_LOGIC_VECTOR(7 DOWNTO 0);
SIGNAL dev_addr     : STD_LOGIC_VECTOR(7 DOWNTO 0);
SIGNAL input_valid  : STD_LOGIC;
SIGNAL data_valid   : STD_LOGIC;
SIGNAL error        : STD_LOGIC;
SIGNAL num_of_bytes : INTEGER;

BEGIN

  i2c : i2c_master
  PORT MAP (
    clk       => clk,
    rst_n     => rst_n,
  
    data_in   => data_in,
    input_valid => input_valid,
    num_of_bytes => num_of_bytes,
    data_out => data_out,
    data_valid => data_valid,
    error => error,
    dev_addr => dev_addr,
  
    scl => scl,
    sda => sda
  );
  
  ctrl : mpu6050_ctrl
  PORT MAP (
    clk       => clk,
    rst_n     => rst_n,
  
    data_in   => data_in,
    input_valid => input_valid,
    num_of_bytes => num_of_bytes,
    data_out => data_out,
    data_valid => data_valid,
    error => error,
    dev_addr => dev_addr,
  
    led_o => led_o
  );


END ARCHITECTURE;