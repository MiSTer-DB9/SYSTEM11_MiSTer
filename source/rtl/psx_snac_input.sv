`timescale 1ns/1ps

// PlayStation controller polling over the MiSTer PSX SNAC pinout.
//
// System 11 does not use the PlayStation SIO0 controller bus, so physical SNAC
// controllers must be polled here and translated into the cabinet input blocks.
// The transport timing and pin mapping follow MiSTer-devel/PSX_MiSTer. Controller
// IDs and payloads used here are the native PSX formats:
//   0x23 neGcon, 0x41 digital, 0x53 analog joystick, 0x63 GunCon,
//   0x73 analog/DualShock, 0xE3 JogCon.
module psx_snac_input #(
	parameter [15:0] HALF_PERIOD      = 16'd68,   // 33.8688 MHz / (2 * 68) ~= 249 kHz
	parameter [15:0] SELECT_DELAY     = 16'd255,
	parameter [15:0] ACK_TIMEOUT      = 16'd1800,
	parameter [15:0] INTERBYTE_DELAY  = 16'd173,
	// Tested PSX hosts leave ATT high for about 50 us between transactions.
	parameter [15:0] DESELECT_DELAY   = 16'd1694
) (
	input  wire       clk,
	input  wire       reset,
	input  wire       enable_p1,
	input  wire       enable_p2,
	input  wire       frame_sync,
	input  wire       data_in,
	input  wire       ack_in,

	output reg        select1_n = 1'b1,
	output reg        select2_n = 1'b1,
	output reg        command = 1'b1,
	output reg        serial_clk = 1'b1,

	output reg        p1_connected = 1'b0,
	output reg        p1_sample_valid = 1'b0,
	output reg  [7:0] p1_device_id = 8'h00,
	output reg [15:0] p1_buttons = 16'h0000,
	output reg signed [7:0] p1_left_x = 8'sd0,
	output reg signed [7:0] p1_left_y = 8'sd0,
	output reg        p1_drive_valid = 1'b0,
	output reg signed [7:0] p1_drive_steer = 8'sd0,
	output reg  [7:0] p1_drive_throttle = 8'h00,
	output reg        p1_gun_aim_valid = 1'b0,
	output reg  [8:0] p1_gun_raw_x = 9'd0,
	output reg  [8:0] p1_gun_raw_y = 9'd0,
	output reg  [9:0] p1_gun_x = 10'd512,
	output reg  [7:0] p1_gun_y = 8'd128,

	output reg        p2_connected = 1'b0,
	output reg        p2_sample_valid = 1'b0,
	output reg  [7:0] p2_device_id = 8'h00,
	output reg [15:0] p2_buttons = 16'h0000,
	output reg signed [7:0] p2_left_x = 8'sd0,
	output reg signed [7:0] p2_left_y = 8'sd0,
	output reg        p2_drive_valid = 1'b0,
	output reg signed [7:0] p2_drive_steer = 8'sd0,
	output reg  [7:0] p2_drive_throttle = 8'h00,
	output reg        p2_gun_aim_valid = 1'b0,
	output reg  [8:0] p2_gun_raw_x = 9'd0,
	output reg  [8:0] p2_gun_raw_y = 9'd0,
	output reg  [9:0] p2_gun_x = 10'd512,
	output reg  [7:0] p2_gun_y = 8'd128
);

	localparam [3:0] ST_IDLE       = 4'd0;
	localparam [3:0] ST_SELECT     = 4'd1;
	localparam [3:0] ST_CLOCK_HIGH = 4'd2;
	localparam [3:0] ST_CLOCK_LOW  = 4'd3;
	localparam [3:0] ST_WAIT_ACK   = 4'd4;
	localparam [3:0] ST_GAP        = 4'd5;
	localparam [3:0] ST_FINISH     = 4'd6;
	localparam [3:0] ST_DESELECT   = 4'd7;

	reg [3:0] state = ST_IDLE;
	reg [15:0] timer = 16'd0;
	reg [3:0] byte_index = 4'd0;
	reg [3:0] last_byte_index = 4'd8;
	reg [2:0] bit_index = 3'd0;
	reg [7:0] tx_shift = 8'hFF;
	reg [7:0] rx_shift = 8'h00;
	reg [7:0] rx_bytes [0:8];

	reg active_port = 1'b0;
	reg pending_p1 = 1'b0;
	reg pending_p2 = 1'b0;

	reg data_meta = 1'b1;
	reg data_sync = 1'b1;
	reg ack_meta = 1'b1;
	reg ack_sync = 1'b1;
	reg [3:0] ack_history = 4'hF;
	reg frame_meta = 1'b0;
	reg frame_sync_s = 1'b0;
	reg frame_sync_d = 1'b0;
	reg enable_any_d = 1'b0;

	wire enable_any = enable_p1 | enable_p2;
	wire ack_low = ~|ack_history;
	wire frame_event = frame_sync_s & ~frame_sync_d;
	wire enable_event = enable_any & ~enable_any_d;
	wire [7:0] received_byte = {data_sync, rx_shift[6:0]};

	wire [7:0] decoded_id = rx_bytes[1];
	wire response_valid = (rx_bytes[2] == 8'h5A)
	                   && (decoded_id != 8'h00)
	                   && (decoded_id != 8'hFF);
	wire [15:0] decoded_buttons = response_valid ? ~{rx_bytes[4], rx_bytes[3]}
	                                             : 16'h0000;

	wire gun_response = response_valid && (decoded_id == 8'h63);
	wire [8:0] decoded_gun_x = {rx_bytes[6][0], rx_bytes[5]};
	wire [8:0] decoded_gun_y = {rx_bytes[8][0], rx_bytes[7]};
	wire gun_coordinates_valid = gun_response
	                          && (decoded_gun_x >= 9'h04D) && (decoded_gun_x <= 9'h1CD)
	                          && (decoded_gun_y >= 9'h019) && (decoded_gun_y <= 9'h0F8);

	// GunCon NTSC coordinates are X=0x04D..0x1CD and Y=0x019..0x0F8.
	// X maps exactly to 0..1023 with (x-77)*341/128. Y uses a sub-pixel
	// approximation of (y-25)*255/223: *293/256, clamped at the endpoint.
	wire [8:0] decoded_gun_x_offset = decoded_gun_x - 9'h04D;
	wire [8:0] decoded_gun_y_offset = decoded_gun_y - 9'h019;
	wire [17:0] gun_x_product = decoded_gun_x_offset * 9'd341;
	wire [17:0] gun_y_product = decoded_gun_y_offset * 9'd293;
	wire [9:0] decoded_gun_aim_x = gun_x_product[16:7];
	wire [8:0] decoded_gun_aim_y_wide = gun_y_product[16:8];
	wire [7:0] decoded_gun_aim_y = decoded_gun_aim_y_wide[8] ? 8'hFF
	                                                        : decoded_gun_aim_y_wide[7:0];

	function automatic signed [7:0] decode_jogcon_steer(
		input [7:0] position,
		input [7:0] turn_state
	);
	begin
		// Match the hardware-tested PsxNewLib decode: byte 6 selects the
		// direction side, byte 5 supplies position, and motion beyond a useful
		// half-turn is clamped to the cabinet steering range.
		if (!turn_state[7])
			decode_jogcon_steer = (position < 8'h80) ? $signed(position) : 8'sd127;
		else
			decode_jogcon_steer = (position > 8'h80) ? $signed(position) : -8'sd127;
	end
	endfunction

	wire drive_response = response_valid
	                   && ((decoded_id == 8'h23) || (decoded_id == 8'hE3));
	wire signed [7:0] decoded_drive_steer =
		(decoded_id == 8'h23) ? $signed(rx_bytes[5] - 8'h80) :
		(decoded_id == 8'hE3) ? decode_jogcon_steer(rx_bytes[5], rx_bytes[6]) :
		                       8'sd0;
	wire [7:0] decoded_drive_throttle =
		(decoded_id == 8'h23) ? rx_bytes[6] :
		(decoded_id == 8'hE3) ? (decoded_buttons[14] ? 8'hFF : 8'h00) :
		                       8'h00;

	wire analog_response = response_valid
	                    && ((decoded_id == 8'h53)
	                     || (decoded_id[7:4] == 4'h7));
	wire signed [7:0] decoded_left_x =
		drive_response ? decoded_drive_steer :
		analog_response ? $signed(rx_bytes[7] - 8'h80) :
		                  8'sd0;
	wire signed [7:0] decoded_left_y =
		analog_response ? $signed(rx_bytes[8] - 8'h80) : 8'sd0;

	function automatic [7:0] poll_byte(input [3:0] index);
	begin
		case (index)
			4'd0: poll_byte = 8'h01;
			4'd1: poll_byte = 8'h42;
			// JogCon byte 3 is its ddccffff motor command. Zero requests no
			// motor action while retaining position/button input support.
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
		enable_any_d <= enable_any;
		p1_sample_valid <= 1'b0;
		p2_sample_valid <= 1'b0;

		if (reset || !enable_any) begin
			state <= ST_IDLE;
			timer <= 16'd0;
			byte_index <= 4'd0;
			last_byte_index <= 4'd8;
			bit_index <= 3'd0;
			tx_shift <= 8'hFF;
			rx_shift <= 8'h00;
			active_port <= 1'b0;
			pending_p1 <= 1'b0;
			pending_p2 <= 1'b0;
			select1_n <= 1'b1;
			select2_n <= 1'b1;
			command <= 1'b1;
			serial_clk <= 1'b1;
			ack_history <= 4'hF;

			p1_connected <= 1'b0;
			p1_device_id <= 8'h00;
			p1_buttons <= 16'h0000;
			p1_left_x <= 8'sd0;
			p1_left_y <= 8'sd0;
			p1_drive_valid <= 1'b0;
			p1_drive_steer <= 8'sd0;
			p1_drive_throttle <= 8'h00;
			p1_gun_aim_valid <= 1'b0;
			p1_gun_raw_x <= 9'd0;
			p1_gun_raw_y <= 9'd0;
			p1_gun_x <= 10'd512;
			p1_gun_y <= 8'd128;

			p2_connected <= 1'b0;
			p2_device_id <= 8'h00;
			p2_buttons <= 16'h0000;
			p2_left_x <= 8'sd0;
			p2_left_y <= 8'sd0;
			p2_drive_valid <= 1'b0;
			p2_drive_steer <= 8'sd0;
			p2_drive_throttle <= 8'h00;
			p2_gun_aim_valid <= 1'b0;
			p2_gun_raw_x <= 9'd0;
			p2_gun_raw_y <= 9'd0;
			p2_gun_x <= 10'd512;
			p2_gun_y <= 8'd128;

			for (i = 0; i < 9; i = i + 1) rx_bytes[i] <= 8'hFF;
		end
		else begin
			if (!enable_p1) begin
				p1_connected <= 1'b0;
				p1_device_id <= 8'h00;
				p1_buttons <= 16'h0000;
				p1_left_x <= 8'sd0;
				p1_left_y <= 8'sd0;
				p1_drive_valid <= 1'b0;
				p1_drive_steer <= 8'sd0;
				p1_drive_throttle <= 8'h00;
				p1_gun_aim_valid <= 1'b0;
			end
			if (!enable_p2) begin
				p2_connected <= 1'b0;
				p2_device_id <= 8'h00;
				p2_buttons <= 16'h0000;
				p2_left_x <= 8'sd0;
				p2_left_y <= 8'sd0;
				p2_drive_valid <= 1'b0;
				p2_drive_steer <= 8'sd0;
				p2_drive_throttle <= 8'h00;
				p2_gun_aim_valid <= 1'b0;
			end

			if (frame_event || enable_event) begin
				pending_p1 <= enable_p1;
				pending_p2 <= enable_p2;
			end

			case (state)
				ST_IDLE: begin
					select1_n <= 1'b1;
					select2_n <= 1'b1;
					command <= 1'b1;
					serial_clk <= 1'b1;

					if (pending_p1 && enable_p1) begin
						active_port <= 1'b0;
						pending_p1 <= 1'b0;
						select1_n <= 1'b0;
						timer <= SELECT_DELAY;
						byte_index <= 4'd0;
						last_byte_index <= 4'd8;
						for (i = 0; i < 9; i = i + 1) rx_bytes[i] <= 8'hFF;
						state <= ST_SELECT;
					end
					else if (pending_p2 && enable_p2) begin
						active_port <= 1'b1;
						pending_p2 <= 1'b0;
						select2_n <= 1'b0;
						timer <= SELECT_DELAY;
						byte_index <= 4'd0;
						last_byte_index <= 4'd8;
						for (i = 0; i < 9; i = i + 1) rx_bytes[i] <= 8'hFF;
						state <= ST_SELECT;
					end
					else begin
						if (!enable_p1) pending_p1 <= 1'b0;
						if (!enable_p2) pending_p2 <= 1'b0;
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
							rx_bytes[byte_index] <= received_byte;

							// The ID low nibble is the number of 16-bit payload
							// words. Every supported direct-input device is <=3.
							if (byte_index == 4'd1) begin
								if (received_byte[3:0] <= 4'd3)
									last_byte_index <= 4'd2 + {received_byte[2:0], 1'b0};
								else
									last_byte_index <= 4'd8;
							end

							if (byte_index == last_byte_index) begin
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
						select1_n <= 1'b1;
						select2_n <= 1'b1;
						command <= 1'b1;
						serial_clk <= 1'b1;
						if (!active_port) begin
							p1_connected <= 1'b0;
							p1_device_id <= 8'h00;
							p1_buttons <= 16'h0000;
							p1_left_x <= 8'sd0;
							p1_left_y <= 8'sd0;
							p1_drive_valid <= 1'b0;
							p1_drive_steer <= 8'sd0;
							p1_drive_throttle <= 8'h00;
							p1_gun_aim_valid <= 1'b0;
							p1_gun_raw_x <= 9'd0;
							p1_gun_raw_y <= 9'd0;
							p1_gun_x <= 10'd512;
							p1_gun_y <= 8'd128;
						end
						else begin
							p2_connected <= 1'b0;
							p2_device_id <= 8'h00;
							p2_buttons <= 16'h0000;
							p2_left_x <= 8'sd0;
							p2_left_y <= 8'sd0;
							p2_drive_valid <= 1'b0;
							p2_drive_steer <= 8'sd0;
							p2_drive_throttle <= 8'h00;
							p2_gun_aim_valid <= 1'b0;
							p2_gun_raw_x <= 9'd0;
							p2_gun_raw_y <= 9'd0;
							p2_gun_x <= 10'd512;
							p2_gun_y <= 8'd128;
						end
						timer <= DESELECT_DELAY;
						state <= ST_DESELECT;
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
						select1_n <= 1'b1;
						select2_n <= 1'b1;
						command <= 1'b1;
						serial_clk <= 1'b1;

						if (!active_port && enable_p1) begin
							p1_sample_valid <= 1'b1;
							p1_connected <= response_valid;
							p1_device_id <= response_valid ? decoded_id : 8'h00;
							p1_buttons <= decoded_buttons;
							p1_left_x <= decoded_left_x;
							p1_left_y <= decoded_left_y;
							p1_drive_valid <= drive_response;
							p1_drive_steer <= decoded_drive_steer;
							p1_drive_throttle <= decoded_drive_throttle;
							p1_gun_aim_valid <= gun_coordinates_valid;
							p1_gun_raw_x <= decoded_gun_x;
							p1_gun_raw_y <= decoded_gun_y;
							p1_gun_x <= gun_coordinates_valid ? decoded_gun_aim_x : 10'd0;
							p1_gun_y <= gun_coordinates_valid ? decoded_gun_aim_y : 8'd0;
						end
						else if (active_port && enable_p2) begin
							p2_sample_valid <= 1'b1;
							p2_connected <= response_valid;
							p2_device_id <= response_valid ? decoded_id : 8'h00;
							p2_buttons <= decoded_buttons;
							p2_left_x <= decoded_left_x;
							p2_left_y <= decoded_left_y;
							p2_drive_valid <= drive_response;
							p2_drive_steer <= decoded_drive_steer;
							p2_drive_throttle <= decoded_drive_throttle;
							p2_gun_aim_valid <= gun_coordinates_valid;
							p2_gun_raw_x <= decoded_gun_x;
							p2_gun_raw_y <= decoded_gun_y;
							p2_gun_x <= gun_coordinates_valid ? decoded_gun_aim_x : 10'd0;
							p2_gun_y <= gun_coordinates_valid ? decoded_gun_aim_y : 8'd0;
						end
						timer <= DESELECT_DELAY;
						state <= ST_DESELECT;
					end
				end

				ST_DESELECT: begin
					select1_n <= 1'b1;
					select2_n <= 1'b1;
					command <= 1'b1;
					serial_clk <= 1'b1;
					if (timer != 0) timer <= timer - 16'd1;
					else state <= ST_IDLE;
				end

				default: state <= ST_IDLE;
			endcase
		end
	end

endmodule
