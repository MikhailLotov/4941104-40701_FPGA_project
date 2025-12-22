`timescale 1ns / 1ps

module DHT11_driver(
    input logic clk,      
    input logic rst,
    
    input  logic data_in,   
    output logic data_out,  
    output logic data_oe,   
    
    input logic start,
    
    output logic [15:0] Temperature,
    output logic [15:0] Humidity,
    output logic valid,
    output logic error
);


    logic data_in_sync_1, data_in_s;
    always_ff @(posedge clk) begin
        data_in_sync_1 <= data_in;
        data_in_s      <= data_in_sync_1; 
    end


    logic [6:0] clk_cnt; 
    logic tick_1us;

    always_ff @(posedge clk) begin
        if (rst) begin
            clk_cnt <= 0;
            tick_1us <= 0;
        end else begin
            if (clk_cnt == 99) begin 
                clk_cnt <= 0;
                tick_1us <= 1'b1;
            end else begin
                clk_cnt <= clk_cnt + 1;
                tick_1us <= 1'b0;
            end
        end
    end


    typedef enum logic [3:0] {
        IDLE,
        START_LOW,       
        WAIT_PULLUP,     
        WAIT_SENSOR_LOW, 
        WAIT_SENSOR_HIGH,
        WAIT_BIT_START,  
        WAIT_BIT_HIGH,   
        MEASURE_BIT,     
        CHECK_SUM        
    } state_t;

    state_t state;
    
    logic [15:0] timer_us;   
    logic [39:0] shift_reg;  
    logic [5:0]  bit_count;  

  
    logic start_prev;
    logic start_pulse;
    assign start_pulse = start && !start_prev;
    
    always_ff @(posedge clk) start_prev <= start;

   
    assign data_out = 1'b0; 
  
    assign data_oe  = (state == START_LOW); 

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            timer_us <= 0;
            shift_reg <= 0;
            bit_count <= 0;
            Temperature <= 0;
            Humidity <= 0;
            valid <= 0;
            error <= 0;
        end
        else begin

            if (tick_1us) 
                timer_us <= timer_us + 1;
            valid <= 0; 


            case(state)
                IDLE: begin
                    if (start_pulse) begin
                        state <= START_LOW;
                        timer_us <= 0;
                        error <= 0;
                        shift_reg <= 0;
                    end
                end


                START_LOW: begin
                    if (timer_us >= 20000) begin 
                        state <= WAIT_PULLUP;
                        timer_us <= 0;
                    end
                end

                WAIT_PULLUP: begin
                    if (data_in_s == 1'b1) begin
                         state <= WAIT_SENSOR_LOW;
                         timer_us <= 0;
                    end
                    else if (timer_us > 100) begin 
                         state <= IDLE; 
                         error <= 1; 
                    end
                end

                WAIT_SENSOR_LOW: begin
                    if (data_in_s == 1'b0) begin
                        state <= WAIT_SENSOR_HIGH;
                        timer_us <= 0;
                    end
                    else if (timer_us > 100) begin 
                        state <= IDLE;
                        error <= 1;
                    end
                end

                WAIT_SENSOR_HIGH: begin
                    if (data_in_s == 1'b1) begin
                        state <= WAIT_BIT_START; 
                        timer_us <= 0;
                    end
                    else if (timer_us > 150) begin 
                        state <= IDLE;
                        error <= 1;
                    end
                end

                WAIT_BIT_START: begin
                    if (data_in_s == 1'b0) begin
                        state <= WAIT_BIT_HIGH;
                        timer_us <= 0;
                    end
                    else if (timer_us > 150) begin
                        state <= IDLE;
                        error <= 1;
                    end
                end


                WAIT_BIT_HIGH: begin
                    if (data_in_s == 1'b1) begin
                        state <= MEASURE_BIT;
                        timer_us <= 0; 
                    end
                    else if (timer_us > 100) begin
                        state <= IDLE;
                        error <= 1;
                    end
                end


                MEASURE_BIT: begin
                    if (data_in_s == 1'b0) begin

                        if (timer_us > 40)
                            shift_reg <= {shift_reg[38:0], 1'b1};
                        else
                            shift_reg <= {shift_reg[38:0], 1'b0};
                        
                        bit_count <= bit_count + 1;

                        if (bit_count == 39) begin
                            state <= CHECK_SUM;
                        end else begin
                            state <= WAIT_BIT_HIGH; 
                        end
                        timer_us <= 0;
                    end
                    else if (timer_us > 100) begin 
                        state <= IDLE;
                        error <= 1;
                    end
                end

                CHECK_SUM: begin
                    logic [7:0] sum;
                    sum = shift_reg[39:32] + shift_reg[31:24] + shift_reg[23:16] + shift_reg[15:8];
                    
                    if (sum == shift_reg[7:0]) begin
                        Humidity    <= {shift_reg[39:32], shift_reg[31:24]};
                        Temperature <= {shift_reg[23:16], shift_reg[15:8]};
                        valid <= 1'b1;
                        error <= 1'b0;
                    end else begin
                        error <= 1'b1; 
                    end
                    
                    bit_count <= 0;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end            
    end

endmodule