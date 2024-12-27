-- A simple I2C master.
-- Sends and receives data via I2C.
-- A controller places the device address and the data to send on
-- the relevant signals and then pulses the "input_valid" signal.
-- Reading the device is done by setting the device address along with
-- the register address and pulsing the "input_valid" signal. The master
-- then reads the requested register and places the resul on the "data_out"
-- signal and pulses the "data_valid" signal. The controller can request to
-- read or write multiple (consecutive) registers by writing the number of
-- registers to the "num_of_bytes" signal before asserting "input_valid".
-- "scl" frequency is adjustable by setting the generics.

LIBRARY IEEE;
  USE IEEE.NUMERIC_STD.ALL;
  USE IEEE.STD_LOGIC_1164.ALL;

ENTITY i2c_master IS
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
  num_of_bytes : IN INTEGER RANGE 1 TO 20;
  input_valid  : IN STD_LOGIC;

-- Outputs
  data_out     : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
  data_valid   : OUT STD_LOGIC;
  error        : OUT STD_LOGIC
);

END ENTITY;

ARCHITECTURE rtl OF i2c_master IS

-- The period of "scl" and the duty cycle of "scl"
  CONSTANT SCL_PERIOD   : INTEGER := (1000 * g_fpga_clk_freq_mhz) / g_desired_scl_freq_khz;
  CONSTANT SCL_DUTY     : INTEGER := SCL_PERIOD / 2;

-- Constants used to set "sda"
  

-- A counter used for "scl" timing
  SIGNAL scl_cnt        : INTEGER RANGE 0 TO SCL_PERIOD;

-- A counter used to control "sda" timing
  SIGNAL sda_cnt        : INTEGER RANGE 0 TO 

-- Input synch
  SIGNAL sda_1r         : STD_LOGIC;
  SIGNAL sda_2r         : STD_LOGIC; -- Stable
  
  TYPE t_i2c_master_state IS (
    s_idle,      -- Wait for valid inputs
    s_start,     -- Send start command
    s_stop,      -- Send stop command
    s_write,     -- Write data to device
    s_read,      -- Read data from device
    s_ack,       -- Send an "ACK"
    s_check_ack, -- Wait for an "ACK"
    s_error,     -- No "ACK" received
    s_done       -- 
  );
  SIGNAL i2c_master_state : t_i2c_master_state;



BEGIN

-- As "sda" is an inout port, the inputs need to be synchronized to the FPGA clock domain.
-- This is done by "doubble flipping" the input.
  sda_sync : PROCESS(clk, rst) IS
  BEGIN
  
    IF rst = g_reset_active_state THEN
    
      sda_1r    <= '0';
      sda_2r    <= '0';
    
    ELSIF RISING_EDGE(clk) THEN
    
      sda_1r    <= sda;
      sda_2r    <= sda_1r;
    
    END IF;
  
  END PROCESS;

-- Increment and reset the counter used for "scl" -timing.
  scl_counter : PROCESS(clk, rst) IS
  BEGIN

    IF rst = g_reset_active_state THEN

      scl_cnt <= 0;

    ELSIF RISING_EDGE(clk) THEN

      IF scl_cnt = SCL_PERIOD THEN

        scl_cnt <= 0;

      ELSE

        scl_cnt <= scl_cnt + 1;

      END IF;
  
    END IF;

  END PROCESS

-- Control the timing of "scl".
  scl     : PROCESS(clk, rst) IS
  BEGIN

    IF rst = g_reset_active_state THEN
    
      scl    <= 'Z';
    
    ELSIF RISING_EDGE(clk) THEN
    
      IF scl_cnt < SCL_DUTY THEN
      
        scl <= 'Z';
      
      ELSE
      
        scl <= '0';
      
      END IF;
    
    END IF;

  END PROCESS;

  sda     : PROCESS(clk, rst) IS
  BEGIN

IF rst = g_reset_active_state THEN


ELSIF RISING_EDGE(clk) THEN


END IF; 
  
  END PROCESS;

END ARCHITECTURE;