`timescale 1ns/1ps

// GunCon polling over the MiSTer PlayStation SNAC pinout.
//
// The physical signal mapping and timing are derived from the SNAC transport in
// MiSTer-devel/PSX_MiSTer. Namco System 11 does not read the PlayStation SIO0
// controller protocol, so this small host polls the gun directly and exposes a
// normalized absolute position for the System 11 GUN I/F registers.
module guncon_snac #(
	parameter [15:0] HALF_PERIOD      = 16'd68,   // 33.8688 MHz / (2 * 68) ~= 249 kHz
	parameter [15:0] SELECT_DELAY     = 16'd255,
	parameter [15:0] ACK_TIMEOUT      = 16'd1800,
	parameter [15:0] INTERBYTE_DELAY  = 16'd173
) (
	input  wire       clk,
	input  wire       reset,
	input  wire       enable,
	input  wire       frame_sync,
	input  wire       data_in,
	input  wire       ack_in,

	output reg        select_n = 1'b1,
	output reg        command = 1'b1,
	output reg        serial_clk = 1'b1,

	output reg        connected = 1'b0,
	output reg        sample_valid = 1'b0,
	output reg        aim_valid = 1'b0,
	output reg  [8:0] raw_x = 9'd0,
	output reg  [8:0] raw_y = 9'd0,
	output reg  [9:0] aim_x = 10'd512,
	output reg  [7:0] aim_y = 8'd128,
	output reg        trigger = 1'b0,
	output reg        button_a = 1'b0,
	output reg        button_b = 1'b0
);

	localparam [3:0] ST_IDLE       = 4'd0;
	localparam [3:0] ST_SELECT     = 4'd1;
	localparam [3:0] ST_CLOCK_HIGH = 4'd2;
	localparam [3:0] ST_CLOCK_LOW  = 4'd3;
	localparam [3:0] ST_WAIT_ACK   = 4'd4;
	localparam [3:0] ST_GAP        = 4'd5;
	localparam [3:0] ST_FINISH     = 4'd6;

	reg [3:0] state = ST_IDLE;
	reg [15:0] timer = 16'd0;
	reg [3:0] byte_index = 4'd0;
	reg [2:0] bit_index = 3'd0;
	reg [7:0] tx_shift = 8'hFF;
	reg [7:0] rx_shift = 8'h00;
	reg [7:0] rx_bytes [0:8];

	reg data_meta = 1'b1;
	reg data_sync = 1'b1;
	reg ack_meta = 1'b1;
	reg ack_sync = 1'b1;
	reg [3:0] ack_history = 4'hF;
	reg frame_meta = 1'b0;
	reg frame_sync_s = 1'b0;
	reg frame_sync_d = 1'b0;
	reg enable_d = 1'b0;

	wire ack_low = ~|ack_history;
	wire start_poll = (enable & ~enable_d) | (frame_sync_s & ~frame_sync_d);
	wire [8:0] decoded_x = {rx_bytes[6][0], rx_bytes[5]};
	wire [8:0] decoded_y = {rx_bytes[8][0], rx_bytes[7]};
	wire response_valid = (rx_bytes[1] == 8'h63) && (rx_bytes[2] == 8'h5A);
	wire coordinates_valid = response_valid
	                       && (decoded_x >= 9'h04D) && (decoded_x <= 9'h1CD)
	                       && (decoded_y >= 9'h019) && (decoded_y <= 9'h0F8);

	// GunCon NTSC coordinates are X=0x04D..0x1CD and Y=0x019..0x0F8.
	// X maps exactly to 0..1023 with (x-77)*341/128. Y uses a sub-pixel
	// approximation of (y-25)*255/223: *293/256, clamped at the endpoint.
	wire [8:0] decoded_x_offset = decoded_x - 9'h04D;
	wire [8:0] decoded_y_offset = decoded_y - 9'h019;
	wire [17:0] aim_x_product = decoded_x_offset * 9'd341;
	wire [17:0] aim_y_product = decoded_y_offset * 9'd293;
	wire [9:0] decoded_aim_x = aim_x_product[16:7];
	wire [8:0] decoded_aim_y_wide = aim_y_product[16:8];
	wire [7:0] decoded_aim_y = decoded_aim_y_wide[8] ? 8'hFF
	                                                : decoded_aim_y_wide[7:0];

	function automatic [7:0] poll_byte(input [3:0] index);
	begin
		case (index)
			4'd0: poll_byte = 8'h01;
			4'd1: poll_byte = 8'h42;
			default: poll_byte = 8'h00;
		endcase
	end
	endfunction

	integer i;
	always @(posedge clk) begin
		data_meta <= data_in;
		data_sync <= data_meta;
		ack_meta <= ack_in;
		ack_sync <= ack_meta;
		ack_history <= {ack_history[2:0], ack_sync};
		frame_meta <= frame_sync;
		frame_sync_s <= frame_meta;
		frame_sync_d <= frame_sync_s;
		enable_d <= enable;
		sample_valid <= 1'b0;

		if (reset || !enable) begin
			state <= ST_IDLE;
			timer <= 16'd0;
			byte_index <= 4'd0;
			bit_index <= 3'd0;
			tx_shift <= 8'hFF;
			rx_shift <= 8'h00;
			select_n <= 1'b1;
			command <= 1'b1;
			serial_clk <= 1'b1;
			connected <= 1'b0;
			aim_valid <= 1'b0;
			raw_x <= 9'd0;
			raw_y <= 9'd0;
			aim_x <= 10'd512;
			aim_y <= 8'd128;
			trigger <= 1'b0;
			button_a <= 1'b0;
			button_b <= 1'b0;
			ack_history <= 4'hF;
			for (i = 0; i < 9; i = i + 1) rx_bytes[i] <= 8'hFF;
		end
		else begin
			case (state)
				ST_IDLE: begin
					select_n <= 1'b1;
					command <= 1'b1;
					serial_clk <= 1'b1;
					if (start_poll) begin
						select_n <= 1'b0;
						timer <= SELECT_DELAY;
						byte_index <= 4'd0;
						state <= ST_SELECT;
					end
				end

				ST_SELECT: begin
					if (timer != 0) timer <= timer - 16'd1;
					else begin
						tx_shift <= poll_byte(4'd0);
						rx_shift <= 8'h00;
						bit_index <= 3'd0;
						timer <= HALF_PERIOD - 16'd1;
						state <= ST_CLOCK_HIGH;
					end
				end

				ST_CLOCK_HIGH: begin
					if (timer != 0) timer <= timer - 16'd1;
					else begin
						command <= tx_shift[0];
						serial_clk <= 1'b0;
						timer <= HALF_PERIOD - 16'd1;
						state <= ST_CLOCK_LOW;
					end
				end

				ST_CLOCK_LOW: begin
					if (timer != 0) timer <= timer - 16'd1;
					else begin
						serial_clk <= 1'b1;
						rx_shift[bit_index] <= data_sync;
						if (bit_index == 3'd7) begin
							rx_bytes[byte_index] <= {data_sync, rx_shift[6:0]};
							if (byte_index == 4'd8) begin
								timer <= INTERBYTE_DELAY;
								state <= ST_FINISH;
							end
							else begin
								timer <= ACK_TIMEOUT;
								state <= ST_WAIT_ACK;
							end
						end
						else begin
							bit_index <= bit_index + 3'd1;
							tx_shift <= {1'b1, tx_shift[7:1]};
							timer <= HALF_PERIOD - 16'd1;
							state <= ST_CLOCK_HIGH;
						end
					end
				end

				ST_WAIT_ACK: begin
					command <= 1'b1;
					if (ack_low) begin
						timer <= INTERBYTE_DELAY;
						state <= ST_GAP;
					end
					else if (timer != 0) timer <= timer - 16'd1;
					else begin
						select_n <= 1'b1;
						command <= 1'b1;
						serial_clk <= 1'b1;
						connected <= 1'b0;
						aim_valid <= 1'b0;
						trigger <= 1'b0;
						button_a <= 1'b0;
						button_b <= 1'b0;
						state <= ST_IDLE;
					end
				end

				ST_GAP: begin
					if (timer != 0) timer <= timer - 16'd1;
					else begin
						byte_index <= byte_index + 4'd1;
						bit_index <= 3'd0;
						tx_shift <= poll_byte(byte_index + 4'd1);
						rx_shift <= 8'h00;
						timer <= HALF_PERIOD - 16'd1;
						state <= ST_CLOCK_HIGH;
					end
				end

				ST_FINISH: begin
					command <= 1'b1;
					if (timer != 0) timer <= timer - 16'd1;
					else begin
						select_n <= 1'b1;
						command <= 1'b1;
						serial_clk <= 1'b1;
						sample_valid <= 1'b1;
						connected <= response_valid;
						aim_valid <= coordinates_valid;
						raw_x <= decoded_x;
						raw_y <= decoded_y;
						if (coordinates_valid) begin
							aim_x <= decoded_aim_x;
							aim_y <= decoded_aim_y;
						end
						else begin
							aim_x <= 10'd0;
							aim_y <= 8'd0;
						end
						trigger <= response_valid && ~rx_bytes[4][5];
						button_a <= response_valid && ~rx_bytes[3][3];
						button_b <= response_valid && ~rx_bytes[4][6];
						state <= ST_IDLE;
					end
				end

				default: state <= ST_IDLE;
			endcase
		end
	end

endmodule
