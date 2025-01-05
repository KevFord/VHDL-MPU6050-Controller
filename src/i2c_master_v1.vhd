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
  g_simulation           : BOOLEAN := true;
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

END ENTITY;

ARCHITECTURE rtl OF i2c_master IS

-- The period of "scl" and the duty cycle of "scl"
  CONSTANT SCL_PERIOD   : INTEGER := (1000 * g_fpga_clk_freq_mhz) / g_desired_scl_freq_khz;
  CONSTANT SCL_DUTY     : INTEGER := SCL_PERIOD / 2;

-- Constant used to time "sda" to signal and the start / stop condition
  CONSTANT START_STOP   : INTEGER := SCL_DUTY - (SCL_DUTY / 4);
  
-- The "sda" clock should have the same period as the "scl" clock
-- however, the "sda" clock should go toggle half of the "scl" duty
-- before and after "scl" has toggled
  CONSTANT DATA_BEGIN   : INTEGER := SCL_DUTY - (SCL_DUTY / 2);
  CONSTANT DATA_END     : INTEGER := SCL_DUTY + (SCL_DUTY / 2);  

-- Internal "scl" signal, used to detect edges
  SIGNAL scl_1r         : STD_LOGIC;
  SIGNAL scl_2r         : STD_LOGIC;

-- A counter used for "scl" timing
  SIGNAL scl_cnt        : INTEGER RANGE 0 TO SCL_PERIOD;

-- A counter used to control "sda" timing
  SIGNAL sda_cnt        : INTEGER RANGE 0 TO SCL_PERIOD;

-- Input synch
  SIGNAL sda_1r         : STD_LOGIC;
  SIGNAL sda_2r         : STD_LOGIC; -- Stable
  
  TYPE t_i2c_master_state IS (
    s_idle,       -- Wait for valid inputs
    s_start,      -- Send start command
    s_write_addr, -- Write device address to device
    s_write_data, -- Write data to device
    s_read,       -- Read data from device
    s_ack,        -- Send an "ACK"
    s_check_ack,  -- Wait for an "ACK"
    s_error,      -- No "ACK" received
    s_stop,       -- Send stop command
    s_done        -- 
  );
  SIGNAL i2c_master_state : t_i2c_master_state;
  SIGNAL next_i2c_state   : t_i2c_master_state;

-- Internal storages of input signals
  SIGNAL dev_addr_r       : STD_LOGIC_VECTOR(dev_addr'LEFT DOWNTO 0);
  SIGNAL data_in_r        : STD_LOGIC_VECTOR(data_in'LEFT DOWNTO 0);
  SIGNAL num_of_bytes_r   : INTEGER RANGE 1 TO 20;

-- A flag used to enable "scl"
  SIGNAL scl_enable       : STD_LOGIC;

-- Buffer for read data
  SIGNAL read_byte        : STD_LOGIC_VECTOR(7 DOWNTO 0);

-- A counter used as index for reading and writing data
  CONSTANT BIT_INDEX_MAX  : INTEGER := 8;
  SIGNAL bit_index        : INTEGER RANGE 0 TO BIT_INDEX_MAX;

-- A timeout. Decides how long to wait for an "ACK"
  CONSTANT ACK_TIMEOUT    : INTEGER := 50;
  SIGNAL ack_timeout_cnt  : INTEGER RANGE 0 TO ACK_TIMEOUT;

-- A flag indicating an error occured (no "ACK")
  SIGNAL error_flag       : STD_LOGIC;

-- A counter keeping track of how many rising edges have been sent on "scl"
  CONSTANT SCL_ADDR_DONE  : INTEGER := 8;
  CONSTANT SCL_DATA_DONE  : INTEGER := 7;
  CONSTANT SCL_ACK_EDGE   : INTEGER := 9;
  SIGNAL scl_edge_cnt     : INTEGER RANGE 0 TO SCL_ACK_EDGE;

BEGIN

-- Increment and reset the "sda" clock
  sda_clock : PROCESS(clk, rst) IS
  BEGIN
  
    IF rst = g_reset_active_state THEN

      sda_cnt <= 0;
    
    ELSIF RISING_EDGE(clk) THEN
    
      IF sda_cnt = SCL_PERIOD THEN
      
        sda_cnt <= 0;
      
      ELSE
      
        sda_cnt <= sda_cnt + 1;
      
      END IF;
    
    END IF;
  
  END PROCESS;

-- Decrement and reset the bit index signal 
  bit_index_cnt : PROCESS(clk, rst) IS
  BEGIN
  
    IF rst = g_reset_active_state THEN
    
      bit_index <= BIT_INDEX_MAX;
    
    ELSIF RISING_EDGE(clk) THEN
    
      IF sda_cnt = DATA_END AND (i2c_master_state = s_write_addr OR i2c_master_state = s_write_data OR i2c_master_state = s_read) THEN
      
        IF bit_index = 0 THEN
        
          bit_index <= BIT_INDEX_MAX;
        
        ELSE
        
          bit_index <=  bit_index - 1;
        
        END IF;
      
      ELSE
      
        bit_index <= bit_index;
      
      END IF;
    
    END IF;
  
  END PROCESS;

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
  scl_clock : PROCESS(clk, rst) IS
  BEGIN

    IF rst = g_reset_active_state THEN

      scl_edge_cnt <= 0;
      scl_cnt      <= 0;

    ELSIF RISING_EDGE(clk) THEN
  
      IF scl_enable = '1' THEN

        IF scl_cnt = SCL_PERIOD THEN
	    
          IF scl_edge_cnt = SCL_ACK_EDGE THEN
          
            scl_edge_cnt <= 0;
          
          ELSE
          
            scl_edge_cnt <= scl_edge_cnt + 1;
          
          END IF;
	    
          scl_cnt <= 0;
	    
        ELSE
	    
          scl_cnt <= scl_cnt + 1;
	    
        END IF;
	  
      ELSE
      
        scl_cnt <= 0;
        
      END IF;

    END IF;

  END PROCESS;

-- Control "scl".
  scl_process     : PROCESS(clk, rst) IS
  BEGIN

    IF rst = g_reset_active_state THEN

      scl_1r <= '1';
      scl_2r <= '1';
      scl    <= 'Z';

    ELSIF RISING_EDGE(clk) THEN

      scl_2r <= scl_1r;

      IF scl_cnt < SCL_DUTY THEN

        scl    <= 'Z';
        scl_1r <= '1';  

      ELSE

        scl_1r <= '0';
        scl    <= '0';
      
      END IF;
    
    END IF;

  END PROCESS;

  sda_process     : PROCESS(clk, rst) IS
  BEGIN

    IF rst = g_reset_active_state THEN
    
      num_of_bytes_r   <= 1;
      ack_timeout_cnt  <= 0;
      
      scl_enable       <= '0';
      sda              <= 'Z';
      error            <= '0';
      data_valid       <= '0';
      error_flag       <= '0';
    
      dev_addr_r       <= (OTHERS => '0');
      data_in_r        <= (OTHERS => '0');
      data_out         <= (OTHERS => '0');
      read_byte        <= (OTHERS => '0');
	  
      i2c_master_state <= s_idle;
      next_i2c_state   <= s_idle;

    ELSIF RISING_EDGE(clk) THEN
    
      CASE i2c_master_state IS
      
        WHEN s_idle => -- Wait for "input_valid" to be pulsed
      
          error_flag <= '0'; -- Clear the error flags
          error      <= '0';
          scl_enable <= '0'; -- Dissable "scl"


          IF input_valid = '1' THEN -- Sample inputs and go to next state
    
            data_out         <= (OTHERS => '0'); -- Reset the output
            data_valid       <= '0'; -- Clear flag
            scl_enable       <= '1'; -- Start "scl"
            i2c_master_state <= s_start; -- Send start command
            dev_addr_r       <= dev_addr; -- Store inputs
            data_in_r        <= data_in;
            num_of_bytes_r   <= num_of_bytes;
          
          ELSE
            NULL;
          
          END IF;
      
        WHEN s_start => -- Send start command
        
          IF scl_2r = '1' AND scl_1r = '1' THEN -- Bring "sda" low while "scl" is high
          
            IF scl_cnt = START_STOP THEN -- Ensures "sda" is pulled low towards the end of the "scl" high period
            
              sda <= '0';
          
              IF dev_addr_r(0) = '0' THEN -- Check if we are writing or reading
              
                i2c_master_state <= s_write_addr;
              
              ELSE
              
                i2c_master_state <= s_read;
              
              END IF;
            
            ELSE -- Counter not finished, keep tri-state
          
              sda <= 'Z';
            
            END IF;
          
          ELSE -- Clock low or at an edge, keep tri-state
          
            sda <= 'Z';
          
          END IF;
      
        WHEN s_write_addr => -- Write the device address

        -- Check what to output. If the current value
        -- is not zero, "sda" is set to tri-state
          IF bit_index < BIT_INDEX_MAX THEN
       
            IF dev_addr_r(bit_index) /= '0' THEN -- Cannot check for tri-state directly
            
              sda <= 'Z';
            
            ELSE
            
              sda <= '0';
            
            END IF;
	   
          ELSE -- If the index is out of bounds of the buffer, do nothing
            NULL;
          	  
          END IF;
     
        -- Check if this was the last bit
          IF scl_edge_cnt = SCL_ADDR_DONE AND scl_cnt = DATA_END THEN  
     
            i2c_master_state <= s_check_ack; 
            next_i2c_state   <= s_write_data; -- Device address sent, now send data
          
          ELSE -- Not the last bit, do nothing
            NULL;
          
          END IF;

        WHEN s_write_data => -- Write data

        -- Check what to output. If the current value
        -- is not zero, "sda" is set to tri-state
          IF bit_index < BIT_INDEX_MAX THEN
       
            IF data_in_r(bit_index) /= '0' THEN -- Cannot check for tri-state directly
            
              sda <= 'Z';
            
            ELSE
            
              sda <= '0';
            
            END IF;
	   
          ELSE -- If the index is out of bounds of the buffer, do nothing
            NULL;

          END IF;
     
        -- Check if this was the last bit
          IF scl_edge_cnt = SCL_DATA_DONE AND scl_cnt = DATA_END THEN  
     
            i2c_master_state <= s_check_ack; 
            next_i2c_state   <= s_stop; -- The write is complete, send stop
          
          ELSE -- Not the last bit, do nothing
            NULL;
          
          END IF;
    
        WHEN s_read => -- Read from device
    
          IF bit_index < BIT_INDEX_MAX THEN
    	  
            IF sda_2r /= '0' THEN
            
              read_byte(bit_index) <= '1';
            
            ELSE
            
              read_byte(bit_index) <= '0';
            
            END IF;
    	  
          ELSE
            NULL;
            
          END IF;
    
        -- Check if this was the last bit
          IF scl_edge_cnt = SCL_DATA_DONE AND scl_cnt = DATA_END THEN  
    
            i2c_master_state <= s_ack; 
          
          ELSE
            NULL;
          
          END IF;  
      
        WHEN s_ack => -- Send an "ACK"
        
          IF sda_cnt = DATA_BEGIN THEN -- Send an "ACK" in the same fashion as when sending normal data
          
            sda <= '0';
          
          ELSIF sda_cnt = DATA_END THEN
          
            sda <= 'Z';
            i2c_master_state <= s_stop; -- Transaction complete
          
          END IF;
      
        WHEN s_check_ack => -- Wait for an "ACK"
        
          IF scl_1r = '0' AND scl_2r = '1' THEN -- Rising edge of "scl"
      
            IF sda = '0' THEN -- "ACK"
      
              i2c_master_state <= next_i2c_state; -- Go to next state
      
            ELSE -- No "ACK"
      
              i2c_master_state <= s_error;
      
            END IF;
      
          ELSE -- Do nothing until the next rising edge of "scl"
            NULL;
      
          END IF;
        
        WHEN s_error => -- No "ACK" received
      
          error_flag       <= '1';  
          error            <= '1';
          i2c_master_state <= s_stop;
      
        WHEN s_stop => -- Send a stop command
        
          IF scl_1r = '1' AND scl_2r = '1' THEN -- Stop involves bringing "sda" high while "scl" is high
        
            IF scl_cnt = START_STOP THEN -- Ensures "sda" is pulled low towards the end of the "scl" high period
      
              sda <= 'Z';
      
              IF error_flag = '1' THEN -- Check to see if an error occured or if this was an expected stop
              
                i2c_master_state <= s_idle; -- Error occured, go back to idle and wait for new input
              
              ELSE
              
                i2c_master_state <= s_done; -- Intentional stop, output data
              
              END IF;
      
            ELSE -- Hold "sda" low long enough to satisify I2C timing requirements
          
              sda <= '0';
            
            END IF;
        
          ELSE -- Hold "sda" low until "scl" is high
          
            sda <= '0';
          
          END IF;
      
        WHEN s_done => -- Output data or just go to idle
      
        WHEN OTHERS =>
          NULL;
      
      END CASE;
    
    END IF; 
  
  END PROCESS;

END ARCHITECTURE;