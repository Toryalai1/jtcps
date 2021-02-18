/*  This file is part of JTCPS1.
    JTCPS1 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundatinsion, either version 3 of the License, or
    (at your option) any later version.

    JTCPS1 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCPS1.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 18-1-2021 */

module jtcps2_decrypt(
    input             rst,
    input             clk,

    // Key load
    input      [ 7:0] prog_din,
    input             prog_we,

    // Encryption control
    input      [ 2:0] fc,
    input             dec_en,

    // Decoding
    input      [15:0] addr,
    input      [15:0] din,
    output     [15:0] dout
);

wire [63:0] master_key, addr_key;
wire [15:0] addr_range, dec_data;

jtcps2_keyload(
    .rst        ( rst           ),
    .clk        ( clk           ),

    .din        ( prog_din      ),
    .din_we     ( prog_we       ),

    .addr_rng   ( addr_rng      ),
    .key        ( master_key    )
);

jtcps2_fn1(
    .clk        ( clk           ),
    .din        ( addr          ),
    .key        ( master_key    ),
    .dout       ( addr_key      )
);

jtcps2_fn2(
    .din       ( din           ),
    .master_key( master_key    ),
    .key       ( addr_key      ),
    .dout      ( dec_data      )
);

jtcps2_dec_ctrl(
    .fc        ( fc            ),
    .en        ( dec_en        ),
    .din       ( din           ),
    .dec       ( dec_data      ),
    .dout      ( dec_data      )
);

endmodule