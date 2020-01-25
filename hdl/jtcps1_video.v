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
    Date: 13-1-2020 */
    
`timescale 1ns/1ps

// Scroll 1 is 512x512, 8x8 tiles
// Scroll 2 is 1024x1024 16x16 tiles
// Scroll 3 is 2048x2048 32x32 tiles

module jtcps1_video(
    input              rst,
    input              clk,
    input              cen8,        // pixel clock enable

    output     [ 7:0]  vdump,
    output     [ 7:0]  vrender,
    output     [ 8:0]  hdump,
    output             frame,

    // Register configuration
    // Scroll
    input      [15:0]  hpos1,
    input      [15:0]  hpos2,
    input      [15:0]  hpos3,
    input      [15:0]  vpos1,
    input      [15:0]  vpos2,
    input      [15:0]  vpos3,
    // VRAM position
    input      [15:0]  vram1_base,
    input      [15:0]  vram2_base,
    input      [15:0]  vram3_base,
    input      [15:0]  vram_obj_base,
    // palette control
    input      [15:0]  pal_base,
    input      [ 5:0]  pal_page_en, // which palette pages to copy
    // Video RAM interface
    output     [23:1]  vram1_addr,
    input      [15:0]  vram1_data,
    input              vram1_ok,
    output             vram1_cs,

    output     [23:1]  vram2_addr,
    input      [15:0]  vram2_data,
    input              vram2_ok,
    output             vram2_cs,

    output     [23:1]  vram3_addr,
    input      [15:0]  vram3_data,
    input              vram3_ok,
    output             vram3_cs,

    output     [23:1]  vram_obj_addr,
    input      [15:0]  vram_obj_data,
    input              vram_obj_ok,
    output             vram_obj_cs,

    // Video signal
    output             HS,
    output             VS,
    output             HB,
    output             VB,
    output     [ 7:0]  red,
    output     [ 7:0]  green,
    output     [ 7:0]  blue,

    // GFX ROM interface
    output     [22:0]  rom1_addr,    // up to 1 MB
    output     [ 3:0]  rom1_bank,
    output             rom1_half,    // selects which half to read
    input      [31:0]  rom1_data,
    output             rom1_cs,
    input              rom1_ok,

    output     [22:0]  rom2_addr,    // up to 1 MB
    output     [ 3:0]  rom2_bank,
    output             rom2_half,    // selects which half to read
    input      [31:0]  rom2_data,
    output             rom2_cs,
    input              rom2_ok,

    output     [22:0]  rom3_addr,    // up to 1 MB
    output     [ 3:0]  rom3_bank,
    output             rom3_half,    // selects which half to read
    input      [31:0]  rom3_data,
    output             rom3_cs,
    input              rom3_ok,

    output     [19:0]  obj_addr,    // up to 1 MB
    output     [ 3:0]  obj_bank,
    output             obj_half,    // selects which half to read
    input      [31:0]  obj_data,
    output             obj_cs,
    input              obj_ok
    // To frame buffer
    // output     [11:0]  line_data,
    // output     [ 8:0]  line_addr,
    // output             line_wr,
    // input              line_wr_ok
);

wire [ 8:0]     scr1_pxl, scr2_pxl, scr3_pxl, obj_pxl;

wire            line_start;

jtcps1_timing u_timing(
    .rst            ( rst               ),
    .clk            ( clk               ),
    .cen8           ( cen8              ),

    .vdump          ( vdump             ),
    .hdump          ( hdump             ),
    .vrender        ( vrender           ),
    .start          ( line_start        ),
    // to video output
    .HS             ( HS                ),
    .VS             ( VS                ),
    .VB             ( VB                ),
    .HB             ( HB                )
);

jtcps1_gfx_pal u_gfx_pal(
    .scr1       ( rom1_addr[22:10]  ),
    .scr2       ( rom2_addr[22:10]  ),
    .scr3       ( rom3_addr[22:10]  ),
    .offset1    ( rom1_bank         ),
    .offset2    ( rom2_bank         ),
    .offset3    ( rom3_bank         )
);

//`define NOSCROLL1
`ifndef NOSCROLL1
jtcps1_tilemap #(.SIZE(8)) u_scroll1(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .hdump      ( hdump         ),
    .vram_base  ( vram1_base    ),
    .hpos       ( hpos1         ),
    .vpos       ( vpos1         ),
    .start      ( line_start    ),
    .vram_addr  ( vram1_addr    ),
    .vram_data  ( vram1_data    ),
    .vram_ok    ( vram1_ok      ),
    .vram_cs    ( vram1_cs      ),
    .rom_addr   ( rom1_addr     ),
    .rom_data   ( rom1_data     ),
    .rom_cs     ( rom1_cs       ),
    .rom_ok     ( rom1_ok       ),
    .rom_half   ( rom1_half     ),
    .pxl        ( scr1_pxl      )
);
`else 
assign rom1_cs  = 1'b0;
assign scr1_pxl = 9'h1ff;
`endif

//`define NOSCROLL2
`ifndef NOSCROLL2
jtcps1_tilemap #(.SIZE(16)) u_scroll2(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .hdump      ( hdump         ),
    .vram_base  ( vram2_base    ),
    .hpos       ( hpos2         ),
    .vpos       ( vpos2         ),
    .start      ( line_start    ),
    .vram_addr  ( vram2_addr    ),
    .vram_data  ( vram2_data    ),
    .vram_ok    ( vram2_ok      ),
    .vram_cs    ( vram2_cs      ),
    .rom_addr   ( rom2_addr     ),
    .rom_data   ( rom2_data     ),
    .rom_cs     ( rom2_cs       ),
    .rom_ok     ( rom2_ok       ),
    .rom_half   ( rom2_half     ),
    .pxl        ( scr2_pxl      )
);
`else 
assign rom2_cs  = 1'b0;
assign scr2_pxl = 9'h1ff;
`endif

`ifndef NOSCROLL3
jtcps1_tilemap #(.SIZE(32)) u_scroll3(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .hdump      ( hdump         ),
    .vram_base  ( vram3_base    ),
    .hpos       ( hpos3         ),
    .vpos       ( vpos3         ),
    .start      ( line_start    ),
    .vram_addr  ( vram3_addr    ),
    .vram_data  ( vram3_data    ),
    .vram_ok    ( vram3_ok      ),
    .vram_cs    ( vram3_cs      ),
    .rom_addr   ( rom3_addr     ),
    .rom_data   ( rom3_data     ),
    .rom_cs     ( rom3_cs       ),
    .rom_ok     ( rom3_ok       ),
    .rom_half   ( rom3_half     ),
    .pxl        ( scr3_pxl      )
);
`else 
assign rom3_cs  = 1'b0;
assign scr3_pxl = 9'h1ff;
`endif

// Objects
jtcps1_obj u_obj(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),

    // input              HB,
    .VB         ( VB            ),

    .start      ( line_start    ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .hdump      ( hdump         ),
    // control registers
    .vram_base  ( vram_obj_base ),
    .vram_addr  ( vram_obj_addr ),
    .vram_data  ( vram_obj_data ),
    .vram_ok    ( vram_obj_ok   ),
    .vram_cs    ( vram_obj_cs   ),

    .rom_addr   ( obj_addr      ),
    .rom_data   ( obj_data      ),
    .rom_cs     ( obj_cs        ),
    .rom_ok     ( obj_ok        ),
    .rom_half   ( obj_half      ),

    .pxl        ( obj_pxl       )
);

jtcps1_colmix u_colmix(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( cen8          ),
    .HB         ( HB            ),
    .VB         ( VB            ),
    // Scroll data
    .scr1_pxl   ( scr1_pxl      ),
    .scr2_pxl   ( scr2_pxl      ),
    .scr3_pxl   ( scr3_pxl      ),
    .obj_pxl    ( obj_pxl       ),
    // Video
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          )    
);

endmodule