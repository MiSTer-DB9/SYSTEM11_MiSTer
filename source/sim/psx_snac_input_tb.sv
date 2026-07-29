`timescale 1ns/1ps

module psx_snac_input_tb;
	reg clk = 1'b0;
	reg reset = 1'b1;
	reg enable_p1 = 1'b0;
	reg enable_p2 = 1'b0;
	reg frame_sync = 1'b0;
	reg data_in = 1'b1;
	reg ack_in = 1'b1;

	wire select1_n;
	wire select2_n;
	wire command;
	wire serial_clk;
	wire p1_connected;
	wire p1_sample_valid;
	wire [7:0] p1_device_id;
	wire [15:0] p1_buttons;
	wire signed [7:0] p1_left_x;
	wire signed [7:0] p1_left_y;
	wire p1_drive_valid;
	wire signed [7:0] p1_drive_steer;
	wire [7:0] p1_drive_throttle;
	wire p1_gun_aim_valid;
	wire [8:0] p1_gun_raw_x;
	wire [8:0] p1_gun_raw_y;
	wire [9:0] p1_gun_x;
	wire [7:0] p1_gun_y;
	wire p2_connected;
	wire p2_sample_valid;
	wire [7:0] p2_device_id;
	wire [15:0] p2_buttons;
	wire signed [7:0] p2_left_x;
	wire signed [7:0] p2_left_y;
	wire p2_drive_valid;
	wire signed [7:0] p2_drive_steer;
	wire [7:0] p2_drive_throttle;
	wire p2_gun_aim_valid;
	wire [8:0] p2_gun_raw_x;
	wire [8:0] p2_gun_raw_y;
	wire [9:0] p2_gun_x;
	wire [7:0] p2_gun_y;

	psx_snac_input #(
		.HALF_PERIOD(4),
		.SELECT_DELAY(4),
		.ACK_TIMEOUT(100),
		.INTERBYTE_DELAY(16),
		.DESELECT_DELAY(16)
	) dut (
		.clk(clk),
		.reset(reset),
		.enable_p1(enable_p1),
		.enable_p2(enable_p2),
		.frame_sync(frame_sync),
		.data_in(data_in),
		.ack_in(ack_in),
		.select1_n(select1_n),
		.select2_n(select2_n),
		.command(command),
		.serial_clk(serial_clk),
		.p1_connected(p1_connected),
		.p1_sample_valid(p1_sample_valid),
		.p1_device_id(p1_device_id),
		.p1_buttons(p1_buttons),
		.p1_left_x(p1_left_x),
		.p1_left_y(p1_left_y),
		.p1_drive_valid(p1_drive_valid),
		.p1_drive_steer(p1_drive_steer),
		.p1_drive_throttle(p1_drive_throttle),
		.p1_gun_aim_valid(p1_gun_aim_valid),
		.p1_gun_raw_x(p1_gun_raw_x),
		.p1_gun_raw_y(p1_gun_raw_y),
		.p1_gun_x(p1_gun_x),
		.p1_gun_y(p1_gun_y),
		.p2_connected(p2_connected),
		.p2_sample_valid(p2_sample_valid),
		.p2_device_id(p2_device_id),
		.p2_buttons(p2_buttons),
		.p2_left_x(p2_left_x),
		.p2_left_y(p2_left_y),
		.p2_drive_valid(p2_drive_valid),
		.p2_drive_steer(p2_drive_steer),
		.p2_drive_throttle(p2_drive_throttle),
		.p2_gun_aim_valid(p2_gun_aim_valid),
		.p2_gun_raw_x(p2_gun_raw_x),
		.p2_gun_raw_y(p2_gun_raw_y),
		.p2_gun_x(p2_gun_x),
		.p2_gun_y(p2_gun_y)
	);

	always #5 clk = ~clk;

	reg [7:0] response1 [0:8];
	reg [7:0] response2 [0:8];
	reg [7:0] host1 [0:8];
	reg [7:0] host2 [0:8];
	integer device_port = 0;
	integer device_byte = 0;
	integer device_bit = 0;
	integer host_byte = 0;
	integer host_bit = 0;
	reg ack_enable1 = 1'b1;
	reg ack_enable2 = 1'b1;

	function automatic integer response_last(input integer port_number);
	begin
		if (port_number == 1)
			response_last = 2 + (response1[1][3:0] * 2);
		else
			response_last = 2 + (response2[1][3:0] * 2);
	end
	endfunction

	task automatic pulse_ack;
	begin
		repeat (2) @(posedge clk);
		ack_in = 1'b0;
		repeat (8) @(posedge clk);
		ack_in = 1'b1;
	end
	endtask

	task automatic start_device(input integer port_number);
	begin
		device_port = port_number;
		device_byte = 0;
		device_bit = 0;
		host_byte = 0;
		host_bit = 0;
		data_in = 1'b1;
	end
	endtask

	always @(negedge select1_n) start_device(1);
	always @(negedge select2_n) start_device(2);

	always @(negedge serial_clk) begin
		if (!select1_n || !select2_n) begin
			if (device_port == 1)
				data_in = response1[device_byte][device_bit];
			else
				data_in = response2[device_byte][device_bit];
		end
	end

	always @(posedge serial_clk) begin
		if (!select1_n || !select2_n) begin
			if (device_port == 1)
				host1[host_byte][host_bit] = command;
			else
				host2[host_byte][host_bit] = command;

			if (device_bit == 7) begin
				if (device_byte < response_last(device_port)
				    && ((device_port == 1 && ack_enable1)
				        || (device_port == 2 && ack_enable2))) fork
					pulse_ack();
				join_none
				device_byte = device_byte + 1;
				device_bit = 0;
				host_byte = host_byte + 1;
				host_bit = 0;
			end
			else begin
				device_bit = device_bit + 1;
				host_bit = host_bit + 1;
			end
		end
	end

	task automatic frame_pulse;
	begin
		@(posedge clk);
		frame_sync = 1'b1;
		@(posedge clk);
		frame_sync = 1'b0;
	end
	endtask

	task automatic wait_p1_sample;
	integer timeout;
	begin
		timeout = 0;
		while (!p1_sample_valid && timeout < 20000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!p1_sample_valid) $fatal(1, "timeout waiting for P1 sample");
	end
	endtask

	task automatic wait_p2_sample;
	integer timeout;
	begin
		timeout = 0;
		while (!p2_sample_valid && timeout < 20000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!p2_sample_valid) $fatal(1, "timeout waiting for P2 sample");
	end
	endtask

	task automatic load_p1_guncon;
	begin
		response1[0] = 8'hFF;
		response1[1] = 8'h63;
		response1[2] = 8'h5A;
		response1[3] = 8'hF7; // A/Start pressed
		response1[4] = 8'h9F; // trigger/Circle + B/Cross pressed
		response1[5] = 8'h2A; // X = 0x12A
		response1[6] = 8'h01;
		response1[7] = 8'h90; // Y = 0x090
		response1[8] = 8'h00;
	end
	endtask

	task automatic load_p2_digital;
	begin
		response2[0] = 8'hFF;
		response2[1] = 8'h41;
		response2[2] = 8'h5A;
		response2[3] = 8'hDF; // Right pressed
		response2[4] = 8'hBF; // Cross pressed
		response2[5] = 8'hFF;
		response2[6] = 8'hFF;
		response2[7] = 8'hFF;
		response2[8] = 8'hFF;
	end
	endtask

	initial begin
		load_p1_guncon();
		load_p2_digital();
		repeat (4) @(posedge clk);
		reset = 1'b0;
		enable_p1 = 1'b1;
		enable_p2 = 1'b1;
		wait_p1_sample();

		if (!p1_connected || p1_device_id != 8'h63 || !p1_gun_aim_valid)
			$fatal(1, "P1 GunCon was not detected");
		if (p1_gun_raw_x != 9'h12A || p1_gun_raw_y != 9'h090)
			$fatal(1, "P1 GunCon raw coordinates mismatch");
		if (p1_gun_x != 10'd588 || p1_gun_y != 8'd136)
			$fatal(1, "P1 GunCon normalized coordinates mismatch");
		if (!p1_buttons[3] || !p1_buttons[13] || !p1_buttons[14])
			$fatal(1, "P1 GunCon buttons were not decoded");
		if (host1[0] != 8'h01 || host1[1] != 8'h42 || host1[2] != 8'h00)
			$fatal(1, "P1 host command mismatch");

		wait_p2_sample();
		if (!p2_connected || p2_device_id != 8'h41)
			$fatal(1, "P2 digital controller was not detected");
		if (!p2_buttons[5] || !p2_buttons[14])
			$fatal(1, "P2 digital buttons were not decoded");
		if (host2[0] != 8'h01 || host2[1] != 8'h42 || host2[2] != 8'h00)
			$fatal(1, "P2 host command mismatch");
		if (host_byte != 5)
			$fatal(1, "P2 digital poll length mismatch: %0d", host_byte);

		// Native neGcon: twist left and analog I throttle.
		response1[1] = 8'h23;
		response1[3] = 8'hF7;
		response1[4] = 8'hFF;
		response1[5] = 8'h20;
		response1[6] = 8'hC0;
		response1[7] = 8'h40;
		response1[8] = 8'h10;
		frame_pulse();
		wait_p1_sample();
		if (p1_device_id != 8'h23 || !p1_drive_valid)
			$fatal(1, "P1 neGcon was not detected");
		if (p1_drive_steer != -8'sd96 || p1_drive_throttle != 8'hC0)
			$fatal(1, "P1 neGcon analog decode mismatch");
		wait_p2_sample();

		// Native JogCon: clockwise quarter-turn and Cross as acceleration.
		response1[1] = 8'hE3;
		response1[3] = 8'hFF;
		response1[4] = 8'hBF;
		response1[5] = 8'h40;
		response1[6] = 8'h00;
		response1[7] = 8'h01;
		response1[8] = 8'h00;
		frame_pulse();
		wait_p1_sample();
		if (p1_device_id != 8'hE3 || !p1_drive_valid)
			$fatal(1, "P1 JogCon was not detected");
		if (p1_drive_steer != 8'sd64 || p1_drive_throttle != 8'hFF)
			$fatal(1, "P1 JogCon drive decode mismatch");
		wait_p2_sample();

		// JogCon turn-state byte selects each direction side; motion beyond a
		// useful half-turn must saturate instead of wrapping toward centre.
		response1[5] = 8'hC0;
		response1[6] = 8'h01;
		frame_pulse();
		wait_p1_sample();
		if (p1_drive_steer != 8'sd127)
			$fatal(1, "P1 JogCon clockwise clamp mismatch");
		wait_p2_sample();

		response1[5] = 8'h40;
		response1[6] = 8'hFF;
		frame_pulse();
		wait_p1_sample();
		if (p1_drive_steer != -8'sd127)
			$fatal(1, "P1 JogCon counter-clockwise clamp mismatch");
		wait_p2_sample();

		// Unplugging a moving controller must clear every cached analog value,
		// then release the shared bus so P2 can still be polled.
		ack_enable1 = 1'b0;
		frame_pulse();
		wait_p2_sample();
		if (p1_connected || p1_device_id != 8'h00 || p1_buttons != 16'h0000
		    || p1_left_x != 8'sd0 || p1_left_y != 8'sd0
		    || p1_drive_valid || p1_drive_steer != 8'sd0
		    || p1_drive_throttle != 8'h00 || p1_gun_aim_valid)
			$fatal(1, "P1 timeout left stale controller state");
		ack_enable1 = 1'b1;

		// P2 GunCon proves the shared bus scheduler and second select line.
		response2[1] = 8'h63;
		response2[3] = 8'hFF;
		response2[4] = 8'hDF;
		response2[5] = 8'h2A;
		response2[6] = 8'h01;
		response2[7] = 8'h90;
		response2[8] = 8'h00;
		frame_pulse();
		wait_p1_sample();
		wait_p2_sample();
		if (p2_device_id != 8'h63 || !p2_gun_aim_valid || !p2_buttons[13])
			$fatal(1, "P2 GunCon decode failed");

		// GunCon offscreen sentinel remains connected but invalidates aim.
		response1[1] = 8'h63;
		response1[4] = 8'hDF;
		response1[5] = 8'h01;
		response1[6] = 8'h00;
		response1[7] = 8'h0A;
		response1[8] = 8'h00;
		frame_pulse();
		wait_p1_sample();
		if (!p1_connected || p1_gun_aim_valid || !p1_buttons[13])
			$fatal(1, "P1 GunCon offscreen handling failed");

		$display("psx_snac_input_tb PASS");
		$finish;
	end
endmodule
