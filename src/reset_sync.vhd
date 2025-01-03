-- A simple reset sync.
-- Asynchronous reset and synchronous release.
-- Uses a generic to allow use in active high and low situations.

LIBRARY IEEE;
  USE IEEE.STD_LOGIC_1164.ALL;

ENTITY rst_sync IS
GENERIC (
  g_reset_active_state : STD_LOGIC := '1'
);
PORT (
  clk      : IN STD_LOGIC;
  rst_in   : IN STD_LOGIC;

  rst_out  : OUT STD_LOGIC
);

END ENTITY;

ARCHITECTURE rtl OF rst_sync IS

  SIGNAL rst_1r  : STD_LOGIC;
  SIGNAL rst_2r  : STD_LOGIC;

BEGIN

-- Doubble flips the reset signal
  PROCESS IS
  BEGIN

    IF rst = g_reset_active_state THEN

      rst_1r  <= g_reset_active_state;
      rst_2r  <= g_reset_active_state;
      rst_out <= g_reset_active_state;

    ELSIF RISING_EDGE(clk) THEN

      rst_1r   <= rst_in;
      rst_2r   <= rst_1r;
      rst_out  <= rst_2r;

    END IF;

  END PROCESS;

END ARCHITECTURE;