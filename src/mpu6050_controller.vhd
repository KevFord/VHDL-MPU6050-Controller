-- This is the controller for the MPU6050.
-- This component sends all relevant commands to the slave.

LIBRARY IEEE;
  USE IEEE.STD_LOGIC_1164.ALL;
  USE IEEE.NUMERIC_STD.ALL;

ENTITY mpu6050_ctrl IS
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
  led_o      : OUT STD_LOGIC_VECTOR(5 DOWNTO 0)
);

END ENTITY;

ARCHITECTURE rtl OF mpu6050_ctrl IS

-- The address of the MPU6050
  CONSTANT MPU_ADDR       : STD_LOGIC_VECTOR(6 DOWNTO 0) := B"110_1000";

-- The "WHO_AM_I" -register address
  CONSTANT WHO_AM_I_ADDR  : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"75";
-- Expected contents of the "WHO_AM_I" -register, as per the data sheet
  CONSTANT EXPECTED_VALUE : STD_LOGIC_VECTOR(7 DOWNTO 0) := B"0110_1000";
-- Power management register
  CONSTANT PWR_MGT_1_ADDR : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"6B";
-- Data to the power register
  CONSTANT PWR_DATA       : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
-- Clock division
  CONSTANT CLK_DIV_ADDR   : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"19";
  CONSTANT CLK_DIV_DATA   : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"07";


-- FSM
  TYPE t_controller_state IS (
    s_idle,
    s_set_pwr_state,
    s_set_clock_div,
    s_check_who_am_i,
    s_read_accel_x,
    s_read_accel_y,
    s_read_accel_z,
    s_read_gyro_x,
    s_read_gyro_y,
    s_read_gyro_z,
    s_error,
    s_done
  );
  SIGNAL controller_state : t_controller_state;

-- An array of different patterns used to debug by using the LEDs
  CONSTANT NUMBER_OF_LED_STATES : INTEGER := 5;
  TYPE t_led_pattern IS ARRAY (0 TO NUMBER_OF_LED_STATES) OF STD_LOGIC_VECTOR(5 DOWNTO 0);
  CONSTANT LED_PATTERN : t_led_pattern := (
    "101010",
    "111110",
    "110011",
    "011110",
    "001100",
    "000000"
  );
  CONSTANT NO_ACK_RECEIVED  : INTEGER := 0;
  CONSTANT PWR_MGT_1_SET    : INTEGER := 1;
  CONSTANT CLOCK_DIV_SET    : INTEGER := 2;
  CONSTANT WHO_AM_I_FAILED  : INTEGER := 3;
  CONSTANT WAITING          : INTEGER := 4;
  CONSTANT CLEAR_ERROR_LED  : INTEGER := 5;

-- A timer to ensure the leds are visible
  CONSTANT LED_TIMEOUT      : INTEGER := g_fpga_clock_mhz * 100000;
  SIGNAL led_timeout_count  : INTEGER RANGE 0 TO LED_TIMEOUT;

-- Flags 
  SIGNAL addr_sent    : STD_LOGIC;
  SIGNAL data_sent    : STD_LOGIC;


BEGIN

  mpu_control_process : PROCESS(clk, rst_n) IS
  BEGIN

IF rst_n = g_reset_active_state THEN 

  data_in           <= (OTHERS => '0');
  dev_addr          <= (OTHERS => '0');
  num_of_bytes      <= 1;
  led_timeout_count <= 0;
  input_valid       <= '0';
  led_o             <= LED_PATTERN(CLEAR_ERROR_LED);
  controller_state  <= s_idle;
  addr_sent         <= '0';
  data_sent         <= '0';

ELSIF RISING_EDGE(clk) THEN

  input_valid <= '0';

CASE controller_state IS

WHEN s_idle =>
  
  led_o            <= LED_PATTERN(CLEAR_ERROR_LED);
  controller_state <= s_set_pwr_state;
  addr_sent        <= '0';
  data_sent        <= '0';

WHEN s_set_pwr_state =>

IF addr_sent = '0' THEN

  dev_addr         <= MPU_ADDR & '0';
  data_in          <= PWR_MGT_1_ADDR;
  input_valid      <= '1';
  
  IF data_valid = '1' THEN
  
    addr_sent <= '1';
  
  ELSE
  
    led_o <= LED_PATTERN(WAITING);
  
  END IF;

ELSE -- Data sent

  dev_addr         <= MPU_ADDR & '0';
  data_in          <= PWR_DATA;
  input_valid      <= '1';

  IF error = '1' THEN
  
    controller_state <= s_error;
  
  ELSIF data_valid = '1' THEN

    led_o <= LED_PATTERN(PWR_MGT_1_SET);
    data_sent <= '1';
 
  END IF;

    IF led_timeout_count = LED_TIMEOUT AND data_sent = '1' THEN
    
      controller_state  <= s_set_clock_div;
      led_timeout_count <= 0;
      data_sent <= '1';    

    ELSE
    
      led_timeout_count <= led_timeout_count + 1;
    
    END IF;

END IF;

WHEN s_set_clock_div =>

IF addr_sent = '0' THEN

  dev_addr         <= MPU_ADDR & '0';
  data_in          <= CLK_DIV_ADDR;
  input_valid      <= '1';
  
  IF data_valid = '1' THEN
  
    addr_sent <= '1';
  
  ELSE
    
    led_o <= LED_PATTERN(WAITING);
  
  END IF;

ELSE -- Data sent

  dev_addr         <= MPU_ADDR & '0';
  data_in          <= CLK_DIV_DATA;
  input_valid      <= '1';

  IF error = '1' THEN
  
    controller_state <= s_error;
  
  ELSIF data_valid = '1' THEN

    led_o <= LED_PATTERN(CLOCK_DIV_SET);
  
  END IF;

    IF led_timeout_count = LED_TIMEOUT AND data_sent = '1' THEN
    
      controller_state  <= s_check_who_am_i;
      led_timeout_count <= 0;
      data_sent <= '1';    

    ELSE
    
      led_timeout_count <= led_timeout_count + 1;
    
    END IF;

END IF;

WHEN s_check_who_am_i =>

IF addr_sent = '0' THEN

  dev_addr         <= MPU_ADDR & '0';
  data_in          <= WHO_AM_I_ADDR;
  input_valid      <= '1';
  
  IF data_valid = '1' THEN
  
    addr_sent <= '1';
  
  ELSE
    
    led_o <= LED_PATTERN(WAITING);
  
  END IF;

ELSE -- Data sent

  dev_addr    <= MPU_ADDR & '1';
  input_valid <= '1';

  IF error = '1' THEN
  
    controller_state <= s_error;
  
  ELSIF data_valid = '1' THEN
  
  IF data_out = EXPECTED_VALUE THEN
  
    led_o <= data_out(6 DOWNTO 1); -- Contents of WHO_AM_I

  ELSE

    led_o <= "101101";

  END IF;  

  END IF;
  
    IF led_timeout_count = LED_TIMEOUT AND data_sent = '1' THEN
    
      controller_state  <= s_idle;
      led_timeout_count <= 0;
      data_sent <= '1';    
   
    ELSE
    
      led_timeout_count <= led_timeout_count + 1;
    
    END IF;
	
END IF;



WHEN s_read_accel_x =>
WHEN s_read_accel_y =>
WHEN s_read_accel_z =>
WHEN s_read_gyro_x =>
WHEN s_read_gyro_y =>
WHEN s_read_gyro_z =>

  WHEN s_error =>
  
    led_o          <= LED_PATTERN(NO_ACK_RECEIVED);
    
    IF led_timeout_count = LED_TIMEOUT THEN
    
      controller_state  <= s_idle;
      led_timeout_count <= 0;
    
    ELSE
    
      led_timeout_count <= led_timeout_count + 1;
    
    END IF;

WHEN s_done =>

  led_o <= ;


  WHEN OTHERS =>
    NULL;

END CASE;

END IF;

  END PROCESS;






END ARCHITECTURE;