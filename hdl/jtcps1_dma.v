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

// I measured the line DMA header and found these values
// 604ns, 1.64us, 2.06us
// The first one would correspond to a line update with
// no OBJ and no row scroll
// The second, no row scroll, but OBJ is active
// The third, full row scroll and OBJ
// It seems that there is a minimum of ~600ns required
// by the original DMA controller even if no requests are
// in place.
// These three times are matched with this controller implementation
// a fourth case of no OBJ but row scroll active is implemented too
// but I couldn't measure it on the PCB. This fourth case is
// ~1.18us in simulation
//
// When all 6 palettes are enabled, the measured DMA interval is ~782us
// This fits well with copying the palette while still copying one
// OBJ entry per line. Row scrolling is ignored during this time, which
// should always be blanking anyway
// OBJ+PAL interval lasts for 784us in simulation. Given the accuracy of
// the measurement; this could be a perfect match.
// Copying OBJ during PAL is needed also in order to be able to transfer
// the whole OBJ table within one frame

module jtcps1_dma(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              pxl2_cen,

    input              HB,
    input      [ 8:0]  vrender1, // 1 line ahead of vdump
    input              flip,

    // control registers
    input      [15:0]  vram1_base,
    input      [15:0]  hpos1,
    input      [15:0]  vpos1,

    input      [15:0]  vram2_base,
    input      [15:0]  hpos2,
    input      [15:0]  vpos2,

    input      [15:0]  vram3_base,
    input      [15:0]  hpos3,
    input      [15:0]  vpos3,

    // Row scroll
    input      [15:0]  vram_row_base,
    input      [15:0]  row_offset,
    input              row_en,
    output reg [15:0]  row_scr,

    input      [ 7:0]  tile_addr,
    output     [15:0]  tile_data,

    // OBJ
    input      [15:0]  vram_obj_base,
    input      [ 9:0]  obj_table_addr,
    input              obj_dma_ok,
    output     [15:0]  obj_table_data

    // PAL
    input              br_pal,
    output reg         bg_pal,
    input      [17:1]  vram_pal_addr,

    output reg [17:1]  vram_addr,
    input      [15:0]  vram_data,
    input              vram_ok,
    output reg         vram_clr,
    output             vram_cs,
    output reg         br,
    input              bg
);


reg  [15:0] vrenderf, vscr1, vscr2, vscr3, row_scr_next;
reg  [11:0] scan, hstep;
reg  [10:0] vn, hn;
reg  [ 9:0] obj_cnt, vram_scr_base;
reg  [ 7:0] scr_cnt, scr_over;
wire [ 4:0] next_step_task;
reg  [ 4:0] tasks, step_task, cur_task;
wire [ 4:0] next_task;
reg  [ 3:0] step;
reg  [ 2:0] active, swap;

reg         last_HB;
reg         rd_bank, wr_bank;
reg         rd_obj_bank, wr_obj_bank;
reg         scr_wr, obj_wr;
reg         obj_busy, obj_fill, last_obj_dma_ok;

wire        HB_edge  = !last_HB && HB;
wire        tile_ok  = vdump<9'd237 || vdump>9'd257; // VB is 38 lines
wire        tile_vs  = vdump==9'd12; // Vertical start, use for SCR3

// various addresses
wire [17:1] vrow_addr = { vram_row_base[9:1], 8'd0 } + 
                        { 7'd0, row_offset[9:0] + vrenderf },
            vscr_addr = { vram_scr_base[9:1], 8'd0 } + { 4'd0, scan, scr_cnt[0] },
            vobj_addr = { vram_obj_base[9:1], 8'd0 } + { 7'd0, obj_cnt[9:2], ~obj_cnt[1:0] };

localparam [7:0] LAST_SCR1 = 8'd99, LAST_SCR2 = 8'd225, LAST_SCR2 = 8'd255;

always @(*) begin
    casez( scr_cnt[8:6] )
        3'b0??:  wr_bank = ~active[0]; // SCR1
        3'b111:  wr_bank = ~active[2]; // SCR3
        default: wr_bank = ~active[1]; // SCR2
    endcase
    rd_bank = !tile_addr[7] ? active[0] : ( // SCR1
        tile_addr <= LAST_SCR2 ? active[1] : // SCR2
                            active[2]); // SCR3
end

// Tile cache
jtframe_dual_ram #(.dw(16), .aw(9)) u_tile_cache(
    .clk0   ( clk           ),
    .clk1   ( clk           ),
    // Port 0: write
    .data0  ( vram_data     ),
    .addr0  ( { wr_bank, scr_cnt    } ),
    .we0    ( scr_wr        ),
    .q0     (               ),
    // Port 1: read
    .data1  ( ~16'd0        ),
    .addr1  ( { rd_bank, tile_addr  } ),
    .we1    ( 1'b0          ),
    .q1     ( tile_data     )
);

// OBJ table
jtframe_dual_ram #(.dw(16), .aw(11)) u_obj_cache(
    .clk0   ( clk           ),
    .clk1   ( clk           ),
    // Port 0: write
    .data0  ( vram_data & {16{~obj_fill}} ),
    .addr0  ( { wr_obj_bank, obj_cnt } ),
    .we0    ( obj_wr        ),
    .q0     (               ),
    // Port 1: read
    .data1  ( ~16'd0        ),
    .addr1  ( { rd_obj_bank, obj_table_addr  } ),
    .we1    ( 1'b0          ),
    .q1     ( obj_table_data)
);

always @(*) begin
    if( bus_master[SCR1] ) begin
        scan   = { vn[8],   hn[8:3], vn[7:3] };
        hstep  = 11'd8;
    end else if( bus_master[SCR2] ) begin
        scan   = { vn[9:8], hn[9:4], vn[7:4] };
        hstep  = 11'd16;
    end else begin
        scan   = { vn[10:8], hn[10:5], vn[7:5] };
        hstep  = 11'd32;
    end
end

assign vram_cs = br;
assign next_step_task = step_task<<1;
assign next_task      = step_task & tasks;

always @(posedge clk) begin
    if( rst ) begin
        tasks      <= 5'd0;
        cur_task   <= 5'd0;
        step_task  <= 5'd1;
        last_HB    <= 0;
        br         <= 0;
        step       <= 4'd1;
        line_req   <= 0;
        active     <= 3'b0;
        swap       <= 3'b0;
        last_obj_dma_ok <= 0;
        // banks
        rd_obj_bank <= 0;
        wr_obj_bank <= 1;
        scr_wr      <= 0;
        obj_wr      <= 0;
        // OBJ
        obj_fill    <= 0;
        obj_cnt     <= 10'd0;
        obj_busy    <= 0;
    end else if(pxl2_cen) begin
        last_HB <= HB;
        last_obj_dma_ok <= obj_dma_ok;

        vscr1  <= vpos1 + vrenderf;
        vscr2  <= vpos2 + vrenderf;
        vscr3  <= vpos3 + vrenderf;

        if( obj_dma_ok && !last_obj_dma_ok ) begin
            obj_busy <= 1;
            obj_fill <= 0;
        end

        if( HB_edge ) begin
            line_req <= 1;
            active   <= active ^ swap;
            swap     <= 3'd0;
            vrenderf <= {7'd0, (vrender1 ^ { 1'b0, {8{flip}}}) + (flip ? -9'd8 : 9'd1) };
            // It'd be better to use a vrender2 signal generated in the timing module
            // but adding 1 to vrender1 doesn't seem to create artifacts
            // note that adding 2 to vrender does create problems in the top horizontal line
        end

        if( line_req && step[3] ) begin
            line_req    <= 0;
            obj_busy    <= 0;
            tasks[OBJ]  <= (tasks[OBJ] | obj_busy) & ~obj_fill;
            tasks[ROW]  <= row_en & tile_ok;
            tasks[SCR1] <= vscr1[2:0]==3'd0 && tile_ok;
            tasks[SCR2] <= vscr2[3:0]=={ flip, 3'd0 } && tile_ok;
            tasks[SCR3] <= (vscr3[3:0]=={ flip, 3'd0 } && tile_ok) || tile_vs;
            scr_cnt     <= 9'd0;
            cur_task    <= 5'b0;
            step_task   <= 5'b1;
            adv         <= 1;
            vram_scr_base <= vram1_base;
            row_scr     <= row_en ? row_scr_next : {12'b0, hpos2[3:0] };
            if( obj_busy ) obj_cnt <= 10'd0;
        end else
        if( !bg ) begin
            if( tasks!=5'd0 ) br<=1;
        end else
        if( bg ) begin
            if( adv ) begin
                step_task <= next_step_task;
                cur_task  <= next_task;
                adv       <= 0;
                if( !step_task ) br <= 0;
                // Update SCR base pointer
                if( next_task[SCR1] ) begin
                    vn <= vscr1;
                    hn        <= 11'h38 + { hpos1[10:3], 3'b0 };
                    scr_cnt   <= 9'd0;
                    scr_over  <= LAST_SCR1;
                    swap[0]   <= 1'b1;
                    vram_scr_base <= vram2_base;
                end
                if( next_task[SCR2] ) begin
                    vn <= vscr2;
                    hn <= 11'h30 + { hpos2[10:4], 4'b0 };
                    scr_cnt   <= 9'd128<<1;
                    scr_over  <= LAST_SCR2;
                    swap[1]   <= 1'b1;
                    vram_scr_base <= vram2_base;
                end
                if( next_task[SCR3]) begin
                    vn <= vscr3;
                    hn <= 11'h20 + { hpos3[10:5], 5'b0 };
                    scr_cnt   <= (LAST_SCR2+1)<<1;
                    scr_over  <= LAST_SCR2;
                    vram_scr_base <= vram3_base;
                    swap[2]   <= 1'b1;
                end
            end
            else begin
                step <= { step[2:0], step[3] };
                case( step ) // 250us to go through all four steps
                    4'd1: begin // request data
                        vram_addr <= cur_task[ROW]       ? vrow_addr : (
                                     cur_task[SCR3:SCR1] ? vscr_addr : (
                                     cur_task[OBJ]       ? vobj_addr :
                                     vpal_addr ));
                    end
                    4'd4: begin // collect data
                        scr_wr <= |cur_task[SCR3:SCR1];
                        obj_wr <= cur_task[OBJ] | obj_fill;
                        if( cur_task[ROW] )
                            row_scr_next <= {12'b0, hpos2[3:0] } + vram_data;
                        if( cur_task[OBJ] && obj_cnt[1:0]==2'b11 && vram_data[15:8]==8'hff ) begin
                            obj_fill <= 1;
                        end
                    end
                    4'd8: begin
                        scr_wr <= 0;
                        if( cur_task[SCR3:SCR1] ) begin
                            if( scr_cnt==scr_over ) begin
                                scr_cnt <= 0;
                                adv     <= 1;
                                if( cur_task[SCR1] ) tasks[SCR1] <= 0;
                                if( cur_task[SCR2] ) tasks[SCR2] <= 0;
                                if( cur_task[SCR3] ) tasks[SCR3] <= 0;
                            end 
                            else scr_cnt<=scr_cnt+1;
                        end else
                        if( cur_task[ROW] ) adv <= 1;
                        if( cur_task[OBJ] || obj_fill ) begin
                            obj_cnt <= obj_cnt + 10'd1;
                            if( &obj_cnt ) begin
                                cur_task[OBJ] <= 0;
                                obj_fill      <= 0;
                                obj_busy      <= 0;
                            end
                        end
                    end
                endcase
            end
        end
    end
end

endmodule