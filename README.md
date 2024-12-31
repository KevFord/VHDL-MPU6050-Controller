# FPGA-based MPU6050 controller
This is a hobby project in which I attempt to interface a cheap Tang Nano 9K FPGA development board to an MPU6050 breakout board.
The FPGA will communicate with the MPU6050 board using the I<sup>2</sup>C protocol running in fast mode (400 kHz).

## Overview
The goal of this project is to read data from the IMU onboard the MPU6050 breakout board.
The data will be digitally filtered by the FPGA and eventually passed on to a computer via UART.

There will be a Python script for reading and graphing the data read from the serial port.

I only know VHDL so this is the HDL used in this project.

A secondary goal is to improve my git skills, so expect git noob errors and mistakes.

## Tools used during development
As I am targeting the Tang Nano board I am using the Gowin tools for synthesis and PNR. Any constraint files will be Gowin specific.
All simulations are done using the _"Altera starter edition"_ of Modelsim, as this is what I have at hand.

I use Notepad++.

## Portability
I intend to make all of the code as generic as possible to improve portability of the design.
**NOTE**: _This does not apply to constraint files, as mentioned above_.

No vendor specific IP will be used.
