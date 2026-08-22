module uart_tb();
module uart_tb();

    // PORT DECLARATIONS
    reg     reset          ;
    reg     rxclk       = 0   ;
    reg     uld_rx_data    ;
    wire    [7:0] rx_data  ;
    reg     rx_enable      ;
    reg     rx_in          ;
    wire    rx_empty       ;

    reg        txclk      = 0    ;
    reg        ld_tx_data     ;
  reg  [9:0] tx_data        ;
    reg        tx_enable      ;
    wire       tx_out         ;
    wire       tx_empty       ;
    // MODULE CONNECTIONS
    uart_tx utx(.reset(reset),.txclk(txclk),.ld_tx_data(ld_tx_data),.tx_data(tx_data),.tx_enable(tx_enable),.tx_out(tx_out),.tx_empty(tx_empty));
    
    uart_rx urx(.reset(reset),.rxclk(rxclk),.uld_rx_data(uld_rx_data),.rx_data(rx_data),.rx_enable(rx_enable),.rx_in(rx_in),.rx_empty(rx_empty));
       // CLOCK
    initial 
        begin
            forever begin
                #16 txclk = ~txclk;
            
            end
        end
  	initial 
        begin
            forever begin
                #1 rxclk = ~rxclk;
                rx_in = tx_out;
            end
        end
  
  	reg error_count = 0;
    event error;
    always@(error)
    begin
    #0 error_count=error_count+1;
    $display(" ERROR RECIVED");
    end 
    // CHECK FOR LOGIC AND TEST
    
    
    parameter dta = 10'h3A;
  	parameter dta2 = 10'hAC;
    initial begin
        $display("RESET in progress");
        reset = 1'b1;
        tx_enable = 1'b0;
        ld_tx_data = 1'b0;
        #10;
        $display("Disabling Reset");
        reset = 1'b0;
        $display("Enabling Transmitter");
        tx_enable = 1'b1;
        ld_tx_data = 1'b1;
        tx_data = dta;
        $display("Sending Byte from Transmitter : %h",tx_data);
        #10;
        ld_tx_data = 1'b0;
        // ENABLE RECIEVER
        $display("Enabling Receiver");
        rx_enable = 1'b1;
        uld_rx_data = 1'b0;
        #500;
        $display("Unloading Serial Data into Parraller Data in Receiver");
        uld_rx_data = 1'b1;
        #50;
        $display("Received Byte from Reciever : %h",rx_data);
        uld_rx_data = 1'b0;
        #100;
      	$display("RESET in progress");
        reset = 1'b1;
        tx_enable = 1'b0;
        ld_tx_data = 1'b0;
        #10;
        $display("Disabling Reset");
        reset = 1'b0;
        $display("Enabling Transmitter");
        tx_enable = 1'b1;
        ld_tx_data = 1'b1;
        tx_data = dta2;
        $display("Sending Byte from Transmitter : %h",tx_data);
        #10;
        ld_tx_data = 1'b0;
        // ENABLE RECIEVER
        $display("Enabling Receiver");
        rx_enable = 1'b1;
        uld_rx_data = 1'b0;
        #500;
        $display("Unloading Serial Data into Parraller Data in Receiver");
        uld_rx_data = 1'b1;
        #50;
        $display("Received Byte from Reciever : %h",rx_data);
        uld_rx_data = 1'b0;
        finish;

    end
    
	// SELF CHECKING BEHAVIOUR
    reg rx_frame_err;
    task finish();
        begin
            if(error_count == 0)
                $display("-----TEST PASSED-----");
            else $display("-----TEST FAILED-----");
            $finish;
        end
    endtask
  
    // EVENT FOR END SIMULATION
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule
