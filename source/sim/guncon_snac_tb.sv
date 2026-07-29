`timescale 1ns/1ps

module guncon_snac_tb;
	reg clk = 1'b0;
	reg reset = 1'b1;
	reg enable = 1'b0;
	reg frame_sync = 1'b0;
	reg data_in = 1'b1;
	reg ack_in = 1'b1;

	wire select_n;
	wire command;
	wire serial_clk;
	wire connected;
	wire sample_valid;
	wire aim_valid;
	wire [8:0] raw_x;
	wire [8:0] raw_y;
	wire [9:0] aim_x;
	wire [7:0] aim_y;
	wire trigger;
	wire button_a;
	wire button_b;

	guncon_snac #(
		.HALF_PERIOD(4),
		.SELECT_DELAY(4),
		.ACK_TIMEOUT(40),
		.INTERBYTE_DELAY(5)
	) dut (
		.clk(clk),
		.reset(reset),
		.enable(enable),
		.frame_sync(frame_sync),
		.data_in(data_in),
		.ack_in(ack_in),
		.select_n(select_n),
		.command(command),
		.serial_clk(serial_clk),
		.connected(connected),
		.sample_valid(sample_valid),
		.aim_valid(aim_valid),
		.raw_x(raw_x),
		.raw_y(raw_y),
		.aim_x(aim_x),
		.aim_y(aim_y),
		.trigger(trigger),
		.button_a(button_a),
		.button_b(button_b)
	);

	always #5 clk = ~clk;

	reg [7:0] response [0:8];
	reg [7:0] host_bytes [0:8];
	integer device_byte = 0;
	integer device_bit = 0;
	integer host_byte = 0;
	integer host_bit = 0;

	task automatic pulse_ack;
	begin
		repeat (2) @(posedge clk);
		ack_in = 1'b0;
		repeat (8) @(posedge clk);
		ack_in = 1'b1;
	end
	endtask

	always @(negedge select_n) begin
		device_byte = 0;
		device_bit = 0;
		host_byte = 0;
		host_bit = 0;
		data_in = 1'b1;
	end

	always @(negedge serial_clk) begin
		if (!select_n) data_in = response[device_byte][device_bit];
	end

	always @(posedge serial_clk) begin
		if (!select_n) begin
			host_bytes[host_byte][host_bit] = command;
			if (device_bit == 7) begin
				if (device_byte < 8) fork
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

	task automatic wait_sample;
	integer timeout;
	begin
		timeout = 0;
		while (!sample_valid && timeout < 10000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!sample_valid) $fatal(1, "timeout waiting for GunCon sample");
	end
	endtask

	task automatic load_valid_response;
	begin
		response[0] = 8'hFF;
		response[1] = 8'h63;
		response[2] = 8'h5A;
		response[3] = 8'hF7; // A pressed (active low bit 3)
		response[4] = 8'h9F; // trigger + B pressed (active low bits 5/6)
		response[5] = 8'h2A; // X = 0x12A
		response[6] = 8'h01;
		response[7] = 8'h90; // Y = 0x090
		response[8] = 8'h00;
	end
	endtask

	initial begin
		load_valid_response();
		repeat (4) @(posedge clk);
		reset = 1'b0;
		enable = 1'b1;
		frame_pulse();
		wait_sample();

		if (!connected || !aim_valid) $fatal(1, "valid GunCon was not detected");
		if (raw_x != 9'h12A || raw_y != 9'h090)
			$fatal(1, "raw coordinates mismatch: x=%h y=%h", raw_x, raw_y);
		if (aim_x != 10'd588 || aim_y != 8'd136)
			$fatal(1, "normalized coordinates mismatch: x=%0d y=%0d", aim_x, aim_y);
		if (!trigger || !button_a || !button_b)
			$fatal(1, "GunCon buttons were not decoded");
		if (host_bytes[0] != 8'h01 || host_bytes[1] != 8'h42)
			$fatal(1, "host command mismatch: %h %h", host_bytes[0], host_bytes[1]);

		// GunCon offscreen sentinel: stay connected, keep trigger, invalidate aim.
		response[5] = 8'h01;
		response[6] = 8'h00;
		response[7] = 8'h0A;
		response[8] = 8'h00;
		frame_pulse();
		wait_sample();
		if (!connected || aim_valid || !trigger)
			$fatal(1, "offscreen response handling failed");

		$display("guncon_snac_tb PASS");
		$finish;
	end
endmodule
