// -----------------------------------------------------------------------------
// uart_tb.v : self-checking testbench for uart_tx / uart_rx (RTL unchanged)
//
// Frame format (from the RTL): 1 start bit, 8 data bits (LSB first), 1 stop
// bit, no parity. tx_data[9:8] are ignored by uart_tx (only tx_data[7:0] is loaded).
// rxclk runs 16x faster than the baud rate (one txclk period = 16 rxclk periods),
// so the RX can detect the start edge and sample each bit near its middle.
//
// Tests
//   T1  directed patterns through loopback
//   T2  50 random bytes through loopback
//   T3  back-to-back frames (unload while the next frame is arriving)
//   T4  frame error: stop bit forced to 0 (error injection, TB drives rx_in)
//   T5  recovery: a good frame is received correctly after a frame error
//   T6  over-run: two frames without unloading
//   T7  false start: a 4-rxclk glitch on the line must be rejected
//   T8  independent TX clock: about +-3% baud offset must still work
// -----------------------------------------------------------------------------
module uart_tb();
    parameter RXCLK = 10;
    integer   TXCLK   = 16*RXCLK;
    reg        reset;
    reg        rxclk = 0, txclk = 0;
    reg        uld_rx_data, rx_enable;
    reg        ld_tx_data, tx_enable;
    reg  [9:0] tx_data;
    wire [7:0] rx_data;
    wire       rx_empty, tx_empty, tx_out;
    reg        use_bb    = 0;
    reg        rx_in_drv = 1;
    wire       rx_in     = use_bb ? rx_in_drv : tx_out;
    uart_tx utx(.reset(reset), .txclk(txclk), .ld_tx_data(ld_tx_data), .tx_data(tx_data),
                .tx_enable(tx_enable), .tx_out(tx_out), .tx_empty(tx_empty));
    uart_rx urx(.reset(reset), .rxclk(rxclk), .uld_rx_data(uld_rx_data), .rx_data(rx_data),
                .rx_enable(rx_enable), .rx_in(rx_in), .rx_empty(rx_empty));
    always #(RXCLK) rxclk = ~rxclk;
    always #(TXCLK) txclk = ~txclk;
    integer error_count = 0;              // failures
    integer checks      = 0;              // checks executed
    integer passed      = 0;              // checks passed (a frame error is NOT a pass)
    integer seed        = 1;

    // The RX fires 'error' when it sees a bad stop bit (hook inside uart_rx.v).
    // T4 injects one on purpose, so it is reported as EXPECTED.
    // Any other frame error is a real failure.
    event   error;
    reg     expect_frame_err = 0;         // set only while the TB is injecting a bad stop bit
    integer frame_err_events = 0;         // all frame errors seen
    integer expected_fe      = 0;         // injected ones that the RX correctly reported
    always @(error) begin
        frame_err_events = frame_err_events + 1;
        if (expect_frame_err) begin
            expected_fe = expected_fe + 1;
            $display("%0t FRAME ERROR reported by RX (expected: stop bit was forced to 0)", $time);
        end
        else begin
            checks      = checks + 1;
            error_count = error_count + 1;
            $display("%0t FAIL: unexpected FRAME ERROR reported by RX", $time);
        end
    end
    
    // Reset 
    task do_reset();
    begin
        reset = 1; use_bb = 0; rx_in_drv = 1;
        tx_enable = 0; rx_enable = 0; ld_tx_data = 0; uld_rx_data = 0; tx_data = 0;
        repeat (4) @(negedge rxclk);
        reset = 0;
        tx_enable = 1; rx_enable = 1;
        repeat (4) @(negedge rxclk);
    end
    endtask

    // Send frame from TX
    task send_tx(input [7:0] d);
    begin
        @(negedge txclk);
        tx_data = {2'b00, d};
        ld_tx_data = 1;
        @(negedge txclk);
        ld_tx_data = 0;
        wait (tx_empty == 1);
    end
    endtask

    // Receive frame from RX and compare 
    task recv_check(input [7:0] exp);
        integer wait_time;
        begin
        wait_time = 0;
            while (rx_empty && wait_time < 400) begin @(posedge rxclk); wait_time = wait_time + 1; end
            checks = checks + 1;
            if (rx_empty) begin
                error_count = error_count + 1;
                $display("%0t FAIL: no frame received (expected %h)", $time, exp);
            end 
            else begin
                @(negedge rxclk); uld_rx_data = 1;
                @(negedge rxclk); uld_rx_data = 0;
                if (rx_data == exp) begin
                    passed = passed + 1;
                    $display("%0t Received data  : %h", $time, rx_data);
                end
                else begin
                    error_count = error_count + 1;
                    $display("%0t FAIL: data mismatch  exp=%h got=%h", $time, exp, rx_data);
                end
            end
        end
    endtask


    // Take control of RX_IN to send custom frames 
    task tb_rx_send(input [7:0] d, input stop);
        integer i;
    begin
        use_bb = 1;
        @(negedge rxclk); rx_in_drv = 0;               repeat (16) @(negedge rxclk);
        for (i = 0; i < 8; i = i + 1) begin
            rx_in_drv = d[i];                          repeat (16) @(negedge rxclk);
        end
        rx_in_drv = stop;                              repeat (16) @(negedge rxclk);
        rx_in_drv = 1;
    end
    endtask

    // Sending a glitch with the custoim RX_IN
    task bb_glitch(input integer cycles);
    begin
        use_bb = 1;
        @(negedge rxclk); rx_in_drv = 0;
        repeat (cycles) @(negedge rxclk);
        rx_in_drv = 1;
        repeat (200) @(negedge rxclk);
        use_bb = 0;
    end
    endtask

    // check(cond, msg): cond is what SHOULD be true.
    // Keep the if/else in this order: if cond is X (unknown), 'if (cond)' is false,
    // so an X result is counted as a failure instead of slipping through.

    task check(input cond, input [8*48:1] msg);
    begin
        checks = checks + 1;
        if (cond) passed = passed + 1;
        else begin
            error_count = error_count + 1;
            $display("%0t FAIL: %0s", $time, msg);
        end
    end
    endtask

    // Tests
    reg [7:0] pat [0:7];
    reg [7:0] b;
    integer   i, j, fe0;
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;

        // Test 1: Custom Patterns
        pat[0]=8'h3A; pat[1]=8'hAC; pat[2]=8'h00; pat[3]=8'hFF;
        pat[4]=8'h55; pat[5]=8'hAA; pat[6]=8'h01; pat[7]=8'h80;
        $display("--- T1: directed patterns");
        do_reset();
        for (i = 0; i < 8; i = i + 1) 
            begin 
                send_tx(pat[i]); 
                recv_check(pat[i]);
            end
        check(frame_err_events == 0, "unexpected frame error in T1");
        
        // Test 2: Random 50 dataframes
        $display("--- T2: 50 random bytes");
        for (i = 0; i < 50; i = i + 1) begin
            b = $random(seed);
            $display("%0t Sent data      : %h", $time, b);
            send_tx(b); 
            recv_check(b);
        end
        check(frame_err_events == 0,    "frame error during random test");
        check(urx.rx_over_run == 1'b0,  "over-run during random test");

        // Test 3: Send data and receive data parallely to check UART functionality
        $display("--- T3: back-to-back frames");
        do_reset();
        send_tx(8'hC3);
        fork recv_check(8'hC3); send_tx(8'h3C); join
        fork recv_check(8'h3C); send_tx(8'hA5); join
        recv_check(8'hA5);
        check(urx.rx_over_run == 1'b0, "over-run flagged during back-to-back frames");
        
        // Test 4: Checking for a frame error, sending stop bit as 0 instead of 1
        // rx_empty wont go low if stop bit is 0
        $display("--- T4: frame error (stop bit = 0)");
        do_reset();
        fe0 = frame_err_events;
        expect_frame_err = 1;
        tb_rx_send(8'hA7, 1'b0);
        repeat (4) @(negedge rxclk);
        check(frame_err_events == fe0 + 1, "frame error not reported");
        check(urx.rx_frame_err == 1'b1,    "rx_frame_err not set");
        check(rx_empty == 1'b1,            "bad frame delivered as valid data");
        repeat (200) @(negedge rxclk);
        use_bb = 0;
        expect_frame_err = 0;
        if (!rx_empty) begin
            $display("INFO: RX accepted a spurious frame after the error ");
            @(negedge rxclk); uld_rx_data = 1; @(negedge rxclk); uld_rx_data = 0;
        end
        
        // Test 5: Check what happens after a frame error
        $display("--- T5: recovery after a frame error");
        send_tx(8'h5E); recv_check(8'h5E);
        check(urx.rx_frame_err == 1'b0, "rx_frame_err not cleared by a good frame");
        
        // Test 6: Send 2 TX while enabling RX after the second
        $display("--- T6: RX over-run (two frames, no unload)");
        do_reset();
        send_tx(8'h11); 
        send_tx(8'h22);
        repeat (40) @(negedge rxclk);
        check(urx.rx_over_run == 1'b1, "rx_over_run not set");
        recv_check(8'h22);

        // Test 7: Check if a glitch is accepted by RX
        // TB pulls rx_in low and back up in under half a bit, mimicking a false start bit
        $display("--- T7: false start (glitches of 1 to 7 rxclk cycles)");
        for (j = 1; j <= 7; j = j + 1) begin
            do_reset;
            fe0 = frame_err_events;
            bb_glitch(j);
            check(rx_empty == 1'b1,        "glitch shorter than half a bit accepted");
            check(frame_err_events == fe0, "glitch caused a frame error");
        end
        send_tx(8'h96); recv_check(8'h96);

        // Test 8: TX clock about 3% slower and 3% faster than nominal (independent clocks)
        $display("--- T8: TX clock offset +-3%% (independent clocks)");
        for (j = 0; j < 2; j = j + 1) begin
            TXCLK = (j == 0) ? (16*RXCLK*97)/100 : (16*RXCLK*103)/100;
            $display("   TXCLK half-period = %0d (nominal %0d)", TXCLK, 16*RXCLK);
            repeat (3) @(posedge txclk);
            do_reset();
            for (i = 0; i < 8; i = i + 1) begin 
                send_tx(pat[i]); 
                recv_check(pat[i]); 
            end
        end
        TXCLK = 16*RXCLK;
        repeat (3) @(posedge txclk);

        $display("checks=%0d  passed=%0d  failed=%0d", checks, passed, error_count);
        $display("frame errors: %0d injected and detected, %0d unexpected",
                 expected_fe, frame_err_events - expected_fe);
        if (error_count == 0 && checks > 0) $display("-----TEST PASSED-----");
        else                                $display("-----TEST FAILED-----");
        $finish;
    end
    initial begin
        #10000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
