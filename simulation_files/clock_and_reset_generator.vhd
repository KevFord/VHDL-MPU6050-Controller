-- Clock and reset generator

LIBRARY IEEE;
  USE IEEE.STD_LOGIC_1164.ALL;

ENTITY CLOCK_RESET IS
GENERIC (
  g_reset_release_time_ns     : REAL RANGE 0.0 TO 200.0 := 100.0;
  g_clock_period_ns           : REAL RANGE 1.0 TO 100.0 := 37.037 -- Tang Nano 9k 27 MHz clock
);
PORT (
  clk         : OUT STD_LOGIC;
  rst         : OUT STD_LOGIC;
  rst_n       : OUT STD_LOGIC
);

END ENTITY;

ARCHITECTURE BEHAVE OF CLOCK_RESET IS

  CONSTANT CLK_PERIOD  : TIME := g_clock_period_ns * ns;
  CONSTANT CLK_DUTY    : TIME := CLK_PERIOD / 2;
  CONSTANT RST_RELEASE : TIME := g_reset_release_time_ns * ns;


  SIGNAL clk_int    : STD_LOGIC := '1';
  SIGNAL rst_int    : STD_LOGIC := '1';

BEGIN

  clk   <= clk_int;
  rst   <= rst_int;
  rst_n <= NOT rst_int;

  clock_process : PROCESS IS
  BEGIN
  
    WAIT FOR CLK_DUTY;
	clk_int <= NOT clk_int;
  
  END PROCESS;

  reset_process : PROCESS IS
  BEGIN
  
    WAIT FOR RST_RELEASE;
	rst_int <= NOT rst_int;
	
	WAIT;
  
  END PROCESS;

END ARCHITECTURE;