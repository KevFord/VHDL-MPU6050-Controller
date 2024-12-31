-- I2C master testbench

LIBRARY IEEE;
  USE IEEE.NUMERIC_STD.ALL;
  USE IEEE.STD_LOGIC_1164.ALL;

ENTITY TB IS
END ENTITY;


ARCHITECTURE BEHAVE OF TB IS


-- DUT component
  COMPONENT i2c_master IS
  GENERIC (
    g_reset_active_state   : STD_LOGIC := '1';
    g_fpga_clk_freq_mhz    : INTEGER RANGE 1 TO 200 := 27;
    g_desired_scl_freq_khz : INTEGER RANGE 1 TO 400 := 400
  );
  PORT (
  -- Clock and reset
    clk          : IN STD_LOGIC;
    rst          : IN STD_LOGIC;
  
  -- I2C signals
    scl          : INOUT STD_LOGIC;
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

-- A simple clock and reset generator component
  COMPONENT CLOCK_RESET IS
  GENERIC (
    g_reset_release_time_ns     : REAL RANGE 0.0 TO 200.0 := 100.0;
    g_clock_period_ns           : REAL RANGE 1.0 TO 100.0 := 37.037 -- Tang Nano 9k 27 MHz clock
  );
  PORT (
    clk         : OUT STD_LOGIC;
    rst         : OUT STD_LOGIC;
    rst_n       : OUT STD_LOGIC
  );
  END COMPONENT;

-- Clock and reset signals
  SIGNAL tb_clk     : STD_LOGIC;
  SIGNAL tb_rst     : STD_LOGIC;

-- Signals to the DUT
-- I2C signals
  SIGNAL dut_sda    : STD_LOGIC;
  SIGNAL dut_scl    : STD_LOGIC;
  
-- Control signals. Inputs
  SIGNAL dut_input_valid  : STD_LOGIC := '0';
  SIGNAL dut_data_in      : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
  SIGNAL dut_dev_addr     : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
  SIGNAL dut_num_of_bytes : INTEGER := 1; -- No need to constrain as this is only used in siumulation

-- Control signals. Outputs
  SIGNAL dut_data_out     : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
  SIGNAL dut_data_valid   : STD_LOGIC := '0';
  SIGNAL dut_error        : STD_LOGIC := '0';

-- Some signals to allow the TB to send an "ACK" to fully test the DUT's ability
-- to write data to an I2C device
  SIGNAL start_detected   : STD_LOGIC := '0';
  SIGNAL stop_detected    : STD_LOGIC := '0';
  SIGNAL bit_index        : INTEGER RANGE 0 TO 7 := 7;

BEGIN

  clock_and_reset : CLOCK_RESET
  PORT MAP (
    clk    => tb_clk,
    rst    => tb_rst,
    rst_n  => open -- Not used
  );

  dut : i2c_master
  PORT MAP (
  clk          => tb_clk,
  rst          => tb_rst,
  
  scl          => dut_scl,
  sda          => dut_sda,
  
  data_in      => dut_data_in,
  dev_addr     => dut_dev_addr,
  num_of_bytes => dut_num_of_bytes,
  input_valid  => dut_input_valid,
  
  data_out     => dut_data_out,
  data_valid   => dut_data_valid,
  
  error        => dut_error  
  );

  dut_scl    <= 'H'; -- Weak pull-up
  dut_sda    <= 'H'; -- Weak pull-up

-- Detect and flag start conditions
  start_detection : PROCESS IS
  BEGIN
  
    WAIT UNTIL FALLING_EDGE(dut_sda);
    
    IF dut_scl /= '0' THEN
	
      start_detected <= '1';
      REPORT "Start condition detected.";
    
    ELSE 
    
      start_detected <= '0';
    
    END IF;
  
  END PROCESS;

-- Detect and flag stop conditions
  stop_detection : PROCESS IS
  BEGIN
  
    WAIT UNTIL RISING_EDGE(dut_sda);

    IF dut_scl /= '0' THEN

      stop_detected <= '1';
      REPORT "Stop condition detected.";
    
    ELSE 
    
      stop_detected <= '0';
    
    END IF;
  
  END PROCESS;


  main_test : PROCESS IS
  BEGIN
  
    WAIT UNTIL FALLING_EDGE(tb_rst) FOR 1 us; -- Wait for the reset to be released
	
  -- Send some mock data
    dut_data_in     <= X"55";
    dut_dev_addr    <= X"AA";
    dut_input_valid <= '1'; 
	WAIT FOR 40 ns;
    dut_input_valid <= '0';

    WAIT FOR 1 ms;  
  
    REPORT "Test completed as intended." SEVERITY FAILURE;
    WAIT;
  END PROCESS;



END ARCHITECTURE;