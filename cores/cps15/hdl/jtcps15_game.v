/*  This file is part of JTCPS1.
    JTCPS1 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCPS1 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCPS1.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 26-9-2020 */

module jtcps15_game(
    input           rst,
    input           clk,        // 96   MHz
    `ifdef JTFRAME_CLK96
    input           clk48,      // 48   MHz
    `endif
    output          pxl2_cen,   // 12   MHz
    output          pxl_cen,    //  6   MHz
    output   [7:0]  red,
    output   [7:0]  green,
    output   [7:0]  blue,
    output          LHBL_dly,
    output          LVBL_dly,
    output          HS,
    output          VS,
    // cabinet I/O
    input   [ 3:0]  start_button,
    input   [ 3:0]  coin_input,
    input   [ 9:0]  joystick1,
    input   [ 9:0]  joystick2,
    input   [ 9:0]  joystick3,
    input   [ 9:0]  joystick4,
    // SDRAM interface
    input           downloading,
    output          dwnld_busy,

    // Bank 0: allows R/W
    output   [21:0] ba0_addr,
    output          ba0_rd,
    output          ba0_wr,
    output   [15:0] ba0_din,
    output   [ 1:0] ba0_din_m,  // write mask
    input           ba0_rdy,
    input           ba0_ack,

    // Bank 1: Read only
    output   [21:0] ba1_addr,
    output          ba1_rd,
    input           ba1_rdy,
    input           ba1_ack,

    // Bank 2: Read only
    output   [21:0] ba2_addr,
    output          ba2_rd,
    input           ba2_rdy,
    input           ba2_ack,

    // Bank 3: Read only
    output   [21:0] ba3_addr,
    output          ba3_rd,
    input           ba3_rdy,
    input           ba3_ack,

    input   [31:0]  data_read,
    output          refresh_en,

    // ROM LOAD
    input   [24:0]  ioctl_addr,
    input   [ 7:0]  ioctl_data,
    input           ioctl_wr,
    output  [21:0]  prog_addr,
    output  [15:0]  prog_data,
    output  [ 1:0]  prog_mask,
    output  [ 1:0]  prog_ba,
    output          prog_we,
    output          prog_rd,
    output          prog_rdy,
    // DIP switches
    input   [31:0]  status,     // only bits 31:16 are looked at
    input           dip_pause,
    inout           dip_flip,
    input           dip_test,
    input   [ 1:0]  dip_fxlevel, // Not a DIP on the original PCB
    input   [31:0]  dipsw,
    // Sound output
    output  signed [15:0] snd_left,
    output  signed [15:0] snd_right,
    output          sample,
    input           enable_psg,
    input           enable_fm,
    // Debug
    input   [3:0]   gfx_en
);

// Support for 48MHz
// This is useful for faster simulation
`ifndef JTFRAME_CLK96
wire clk48 = clk;
`endif

wire        LHBL, LVBL; // internal blanking signals
wire        snd_cs, qsnd_cs, main_ram_cs, main_vram_cs, main_rom_cs,
            rom0_cs, rom1_cs,
            vram_dma_cs;
wire        HB, VB;
wire [18:0] snd_addr;
wire [22:0] qsnd_addr;
wire        prog_qsnd;
wire [ 7:0] snd_data, qsnd_data;
wire [17:1] ram_addr;
wire [21:1] main_rom_addr;
wire [15:0] main_ram_data, main_rom_data, main_dout, mmr_dout;
wire        main_rom_ok, main_ram_ok;
wire        ppu1_cs, ppu2_cs, ppu_rstn;
wire [19:0] rom1_addr, rom0_addr;
wire [31:0] rom0_data, rom1_data;
// Video RAM interface
wire [17:1] vram_dma_addr;
wire [15:0] vram_dma_data;
wire        vram_dma_ok, rom0_ok, rom1_ok, snd_ok, qsnd_ok;
wire [15:0] cpu_dout;
wire        cpu_speed;

wire        main_rnw, busreq, busack;
wire [ 7:0] dipsw_a, dipsw_b, dipsw_c;

wire        vram_clr;
wire [ 8:0] hdump;
wire [ 8:0] vdump, vrender;

wire        rom0_half, rom1_half;
wire        cfg_we;

// QSound - Decode keys
wire        kabuki_we;

// M68k - Sound subsystem communication
wire [ 7:0] main2qs_din;
wire [23:1] main2qs_addr;
wire        main2qs_cs, main_busakn;

// EEPROM
wire        sclk, sdi, sdo, scs;

assign { dipsw_c, dipsw_b, dipsw_a } = ~24'd0;
assign dip_flip = 0;

assign LVBL         = ~VB;
assign LHBL         = ~HB;

wire [ 1:0] dsn;
wire        cen16, cen12, cen8, cen10b;
wire        cpu_cen, cpu_cenb;
wire        turbo;

`ifdef JTCPS_TURBO
assign turbo = 1;
`else
assign turbo = status[6];
`endif

// CPU clock enable signals come from 48MHz domain
jtframe_cen48 u_cen48(
    .clk        ( clk48         ),
    .cen16      ( cen16         ),
    .cen12      ( cen12         ),
    .cen8       ( cen8          ),
    .cen6       (               ),
    .cen4       (               ),
    .cen4_12    (               ),
    .cen3       (               ),
    .cen3q      (               ),
    .cen1p5     (               ),
    // 180 shifted signals
    .cen12b     (               ),
    .cen6b      (               ),
    .cen3b      (               ),
    .cen3qb     (               ),
    .cen1p5b    (               )
);

`ifdef JTFRAME_CLK96
jtframe_cen96 u_pxl_cen(
    .clk    ( clk       ),    // 96 MHz
    .cen16  ( pxl2_cen  ),
    .cen8   ( pxl_cen   ),
    // Unused:
    .cen12  (           ),
    .cen6   (           ),
    .cen6b  (           )
);
`else
assign pxl2_cen = cen16;
assign pxl_cen  = cen8;
`endif

jtcps1_cpucen u_cpucen(
    .clk        ( clk48              ),
    .cen12      ( cen12              ),
    .cpu_speed  ( cpu_speed | turbo  ),
    .cpu_cen    ( cpu_cen            ),
    .cpu_cenb   ( cpu_cenb           )
);

localparam REGSIZE=24;

// Turbo speed disables DMA
wire busreq_cpu = busreq & ~turbo;
wire busack_cpu;
assign busack = busack_cpu | turbo;

`ifndef NOMAIN
jtcps1_main u_main(
    .rst        ( rst               ),
    .clk        ( clk48             ),
    .cen10      ( cpu_cen           ),
    .cen10b     ( cpu_cenb          ),
    .cpu_cen    (                   ),
    // Timing
    .V          ( vdump             ),
    .LVBL       ( LVBL              ),
    .LHBL       ( LHBL              ),
    // PPU
    .ppu1_cs    ( ppu1_cs           ),
    .ppu2_cs    ( ppu2_cs           ),
    .ppu_rstn   ( ppu_rstn          ),
    .mmr_dout   ( mmr_dout          ),
    // Sound
    .main2qs_din ( main2qs_din      ),
    .main2qs_addr( main2qs_addr     ),
    .main2qs_cs  ( main2qs_cs       ),
    .main2qs_busakn( main_busakn    ),
    .UDSWn      ( dsn[1]            ),
    .LDSWn      ( dsn[0]            ),
    // cabinet I/O
    // Cabinet input
    .charger     ( 1'b0             ),
    .start_button( start_button     ),
    .coin_input  ( coin_input       ),
    .joystick1   ( joystick1        ),
    .joystick2   ( joystick2        ),
    .joystick3   ( joystick3        ),
    .joystick4   ( joystick4        ),
    .service     ( 1'b1             ),
    .tilt        ( 1'b1             ),
    // BUS sharing
    .busreq      ( busreq_cpu       ),
    .busack      ( busack_cpu       ),
    .RnW         ( main_rnw         ),
    // RAM/VRAM access
    .addr        ( ram_addr         ),
    .cpu_dout    ( main_dout        ),
    .ram_cs      ( main_ram_cs      ),
    .vram_cs     ( main_vram_cs     ),
    .ram_data    ( main_ram_data    ),
    .ram_ok      ( main_ram_ok      ),
    // ROM access
    .rom_cs      ( main_rom_cs      ),
    .rom_addr    ( main_rom_addr    ),
    .rom_data    ( main_rom_data    ),
    .rom_ok      ( main_rom_ok      ),
    // DIP switches
    .dip_pause   ( dip_pause        ),
    .dip_test    ( dip_test         ),
    .dipsw_a     ( dipsw_a          ),
    .dipsw_b     ( dipsw_b          ),
    .dipsw_c     ( dipsw_c          ),
    // EEPROM
    .eeprom_sclk ( sclk             ),
    .eeprom_sdi  ( sdi              ),
    .eeprom_sdo  ( sdo              ),
    .eeprom_scs  ( scs              ),
    // Unused -stuff from CPS1
    .snd_latch0  (                  ),
    .snd_latch1  (                  )
);
`else
assign ram_addr = 17'd0;
assign main_ram_cs = 1'b0;
assign main_vram_cs = 1'b0;
assign main_rom_cs = 1'b0;
assign dsn = 2'b11;
assign main_rnw = 1'b1;
assign sclk = 0;
assign sdo  = 0;
assign scs  = 0;
`endif

reg rst_video, rst_sdram, rst_eprom;

always @(negedge clk) begin
    rst_sdram <= rst;
    rst_video <= rst;
    rst_eprom <= rst;
end

// EEPROM to save game settings
jt9346 #(.DW(16),.AW(7)) u_eeprom(
    .clk    ( clk       ),  // system clock
    .rst    ( rst_eprom ),  // system reset
    // chip interface
    .sclk   ( sclk      ),  // serial clock
    .sdi    ( sdi       ),  // serial data in
    .sdo    ( sdo       ),  // serial data out and ready/not busy signal
    .scs    ( scs       )   // chip select, active high. Goes low in between instructions
);

jtcps1_video #(REGSIZE) u_video(
    .rst            ( rst_video     ),
    .clk            ( clk           ),
    .pxl2_cen       ( pxl2_cen      ),
    .pxl_cen        ( pxl_cen       ),

    .hdump          ( hdump         ),
    .vdump          ( vdump         ),
    .vrender        ( vrender       ),
    .gfx_en         ( gfx_en        ),
    .cpu_speed      ( cpu_speed     ),
    .charger        (               ),

    // CPU interface
    .ppu_rstn       ( ppu_rstn      ),
    .ppu1_cs        ( ppu1_cs       ),
    .ppu2_cs        ( ppu2_cs       ),
    .addr           ( ram_addr[5:1] ),
    .dsn            ( dsn           ),      // data select, active low
    .cpu_dout       ( main_dout     ),
    .mmr_dout       ( mmr_dout      ),
    // BUS sharing
    .busreq         ( busreq        ),
    .busack         ( busack        ),

    // Video signal
    .HS             ( HS            ),
    .VS             ( VS            ),
    .HB             ( HB            ),
    .VB             ( VB            ),
    .LHBL_dly       ( LHBL_dly      ),
    .LVBL_dly       ( LVBL_dly      ),
    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),

    // CPS-B Registers
    .cfg_we         ( cfg_we        ),
    .cfg_data       ( prog_data[7:0]),

    // Extra inputs read through the C-Board
    .start_button   ( start_button  ),
    .coin_input     ( coin_input    ),
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .joystick3      ( joystick3     ),
    .joystick4      ( joystick4     ),

    // Video RAM interface
    .vram_dma_addr  ( vram_dma_addr ),
    .vram_dma_data  ( vram_dma_data ),
    .vram_dma_ok    ( vram_dma_ok   ),
    .vram_dma_cs    ( vram_dma_cs   ),
    .vram_dma_clr   ( vram_clr      ),

    // GFX ROM interface
    .rom1_addr      ( rom1_addr     ),
    .rom1_half      ( rom1_half     ),
    .rom1_data      ( rom1_data     ),
    .rom1_cs        ( rom1_cs       ),
    .rom1_ok        ( rom1_ok       ),
    .rom0_addr      ( rom0_addr     ),
    .rom0_half      ( rom0_half     ),
    .rom0_data      ( rom0_data     ),
    .rom0_cs        ( rom0_cs       ),
    .rom0_ok        ( rom0_ok       )
);

// Sound CPU cannot be disabled as there is
// interaction between both CPUs at power up
jtcps15_sound u_sound(
    .rst        ( rst               ),
    .clk48      ( clk48             ),
    `ifndef QSDEBUG
    .clk96      ( clk               ),
    `else
    .clk96      ( clk48             ), // for fast compilations
    `endif
    .cen8       ( cen8              ),
    .vol_up     ( 1'b0              ),
    .vol_down   ( 1'b0              ),
    // Decode keys
    .kabuki_we  ( kabuki_we         ),

    // Interface with main CPU
    .main_addr  ( main2qs_addr      ),
    .main_dout  ( main_dout[7:0]    ),
    .main_din   ( main2qs_din       ),
    .main_ldswn ( dsn[0]            ),
    .main_buse_n( ~main2qs_cs       ),
    .main_busakn( main_busakn       ),

    // ROM
    .rom_addr   ( snd_addr          ),
    .rom_cs     ( snd_cs            ),
    .rom_data   ( snd_data          ),
    .rom_ok     ( snd_ok            ),

    // QSound sample ROM
    .qsnd_addr  ( qsnd_addr         ), // max 8 MB.
    .qsnd_cs    ( qsnd_cs           ),
    .qsnd_data  ( qsnd_data         ),
    .qsnd_ok    ( qsnd_ok           ),

    // ROM programming interface
    .prog_addr  ( prog_addr[12:0]   ),
    .prog_data  ( prog_data[7:0]    ),
    .prog_we    ( prog_qsnd         ),

    // Sound output
    .left       ( snd_left          ),
    .right      ( snd_right         ),
    .sample     ( sample            )
);

jtcps1_sdram #(.CPS(15), .REGSIZE(REGSIZE)) u_sdram (
    .rst         ( rst           ),
    .clk         ( clk           ),        // 96   MHz
    .LVBL        ( LVBL          ),

    .downloading ( downloading   ),
    .dwnld_busy  ( dwnld_busy    ),
    .cfg_we      ( cfg_we        ),

    // ROM LOAD
    .ioctl_addr  ( ioctl_addr    ),
    .ioctl_data  ( ioctl_data    ),
    .ioctl_wr    ( ioctl_wr      ),
    .prog_addr   ( prog_addr     ),
    .prog_data   ( prog_data     ),
    .prog_mask   ( prog_mask     ),
    .prog_ba     ( prog_ba       ),
    .prog_we     ( prog_we       ),
    .prog_rd     ( prog_rd       ),
    .prog_rdy    ( prog_rdy      ),
    .prog_qsnd   ( prog_qsnd     ),
    // Kabuki decoder (CPS 1.5)
    .kabuki_we   ( kabuki_we     ),

    // Main CPU
    .main_rom_cs    ( main_rom_cs   ),
    .main_rom_ok    ( main_rom_ok   ),
    .main_rom_addr  ( main_rom_addr ),
    .main_rom_data  ( main_rom_data ),

    // VRAM
    .vram_clr       ( vram_clr      ),
    .vram_dma_cs    ( vram_dma_cs   ),
    .main_ram_cs    ( main_ram_cs   ),
    .main_vram_cs   ( main_vram_cs  ),

    .dsn            ( dsn           ),
    .main_dout      ( main_dout     ),
    .main_rnw       ( main_rnw      ),

    .main_ram_ok    ( main_ram_ok   ),
    .vram_dma_ok    ( vram_dma_ok   ),

    .main_ram_addr  ( ram_addr      ),
    .vram_dma_addr  ( vram_dma_addr ),

    .main_ram_data  ( main_ram_data ),
    .vram_dma_data  ( vram_dma_data ),

    // Sound CPU and PCM
    .snd_cs      ( snd_cs        ),
    .pcm_cs      ( qsnd_cs       ),

    .snd_ok      ( snd_ok        ),
    .pcm_ok      ( qsnd_ok       ),

    .snd_addr    ( snd_addr      ),
    .pcm_addr    ( qsnd_addr     ),

    .snd_data    ( snd_data      ),
    .pcm_data    ( qsnd_data     ),

    // Graphics
    .rom0_cs     ( rom0_cs       ),
    .rom1_cs     ( rom1_cs       ),

    .rom0_ok     ( rom0_ok       ),
    .rom1_ok     ( rom1_ok       ),

    .rom0_addr   ( rom0_addr     ),
    .rom1_addr   ( rom1_addr     ),

    .rom0_half   ( rom0_half     ),
    .rom1_half   ( rom1_half     ),

    .rom0_data   ( rom0_data     ),
    .rom1_data   ( rom1_data     ),

    // Bank 0: allows R/W
    .ba0_addr    ( ba0_addr      ),
    .ba0_rd      ( ba0_rd        ),
    .ba0_wr      ( ba0_wr        ),
    .ba0_ack     ( ba0_ack       ),
    .ba0_rdy     ( ba0_rdy       ),
    .ba0_din     ( ba0_din       ),
    .ba0_din_m   ( ba0_din_m     ),

    // Bank 1: Read only
    .ba1_addr    ( ba1_addr      ),
    .ba1_rd      ( ba1_rd        ),
    .ba1_ack     ( ba1_ack       ),
    .ba1_rdy     ( ba1_rdy       ),

    // Bank 2: Read only
    .ba2_addr    ( ba2_addr      ),
    .ba2_rd      ( ba2_rd        ),
    .ba2_ack     ( ba2_ack       ),
    .ba2_rdy     ( ba2_rdy       ),

    // Bank 3: Read only
    .ba3_addr    ( ba3_addr      ),
    .ba3_rd      ( ba3_rd        ),
    .ba3_ack     ( ba3_ack       ),
    .ba3_rdy     ( ba3_rdy       ),

    .data_read   ( data_read     ),
    .refresh_en  ( refresh_en    )
);

endmodule
