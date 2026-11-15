`default_nettype wire

// Independent fully pipelined mining cores sharing the existing UART protocol.
module top_pipelined #(
    parameter CLK_FREQ = 200000000,
    parameter BAUD_RATE = 115200,
    parameter LEDS = 5,
    parameter CORES = 3,
    parameter RESULT_FIFO_DEPTH = 256
) (
    input clk,
    input reset,
    input uart_rx_pin,
    output uart_tx_pin,
    output [LEDS-1:0] led
);
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer JOB_BYTES = 76;
    localparam integer FOUND_RESP_BYTES = 37;
    localparam integer ECHO_RESP_BYTES = 77;
    localparam integer CORE_INDEX_BITS = (CORES <= 1) ? 1 : $clog2(CORES);

    wire [7:0] rx_data;
    wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) rx0 (
        .clk(clk), .reset(reset), .rx(uart_rx_pin),
        .data(rx_data), .valid(rx_valid)
    );

    reg tx_start = 1'b0;
    reg [7:0] tx_data = 8'hff;
    wire tx_busy;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx0 (
        .clk(clk), .reset(reset), .start(tx_start), .data(tx_data),
        .tx(uart_tx_pin), .busy(tx_busy)
    );

    reg [255:0] midstate = 256'd0;
    reg [95:0] tail = 96'd0;
    reg [255:0] target = 256'd0;
    reg [255:0] active_midstate = 256'd0;
    reg [95:0] active_tail = 96'd0;
    reg [255:0] active_target = 256'd0;
    reg core_start = 1'b0;
    reg core_stop = 1'b0;
    reg start_pending = 1'b0;
    reg start_after_load = 1'b0;
    reg flush_results = 1'b0;

    wire [CORES-1:0] core_running;
    wire [CORES-1:0] core_found;
    wire [CORES*32-1:0] core_current_nonce;
    wire [CORES-1:0] core_result_valid;
    wire [CORES*32-1:0] core_result_nonce;
    wire [CORES*256-1:0] core_result_hash;
    wire [CORES-1:0] fifo_empty;
    wire [CORES-1:0] fifo_full;
    wire [CORES-1:0] fifo_overflow;
    wire [CORES*288-1:0] fifo_pop_data;
    reg [CORES-1:0] fifo_pop = {CORES{1'b0}};
    wire fifo_clear = core_start || flush_results;

    genvar core_index;
    generate
        for (core_index = 0; core_index < CORES; core_index = core_index + 1) begin : mining_core
            bitcoin_hash_core #(
                .START_NONCE(core_index),
                .NONCE_STRIDE(CORES)
            ) core_i (
                .clk(clk), .start(core_start), .stop(core_stop),
                .midstate(active_midstate), .tail(active_tail), .target(active_target),
                .running(core_running[core_index]), .found(core_found[core_index]),
                .found_nonce(), .found_hash(),
                .current_nonce(core_current_nonce[core_index*32 +: 32]),
                .result_valid(core_result_valid[core_index]),
                .result_nonce(core_result_nonce[core_index*32 +: 32]),
                .result_hash(core_result_hash[core_index*256 +: 256]),
                .report_byte_out(), .report_load(1'b0), .report_shift(1'b0),
                .report_select(1'b0), .report_bit_index(9'd0), .report_bit_out()
            );

            mining_result_fifo #(
                .DEPTH(RESULT_FIFO_DEPTH), .WIDTH(288)
            ) result_queue (
                .clk(clk), .reset(reset), .clear(fifo_clear),
                .push(core_result_valid[core_index]),
                .push_data({core_result_nonce[core_index*32 +: 32],
                            core_result_hash[core_index*256 +: 256]}),
                .pop(fifo_pop[core_index]),
                .pop_data(fifo_pop_data[core_index*288 +: 288]),
                .empty(fifo_empty[core_index]), .full(fifo_full[core_index]),
                .overflow(fifo_overflow[core_index])
            );
        end
    endgenerate

    localparam R_SYNC0 = 2'd0;
    localparam R_SYNC1 = 2'd1;
    localparam R_CMD = 2'd2;
    localparam R_PAYLOAD = 2'd3;
    reg [1:0] rx_state = R_SYNC0;
    reg [6:0] payload_count = 7'd0;
    reg [7:0] command = 8'd0;
    reg echo_toggle = 1'b0;

    always @(posedge clk) begin
        if (reset) begin
            rx_state <= R_SYNC0;
            payload_count <= 7'd0;
            core_start <= 1'b0;
            core_stop <= 1'b0;
            start_pending <= 1'b0;
            start_after_load <= 1'b0;
            echo_toggle <= 1'b0;
            flush_results <= 1'b0;
        end else begin
            core_start <= 1'b0;
            core_stop <= 1'b0;
            flush_results <= 1'b0;

            if (start_after_load) begin
                core_start <= 1'b1;
                start_after_load <= 1'b0;
            end
            if (start_pending) begin
                active_midstate <= midstate;
                active_tail <= tail;
                active_target <= target;
                start_pending <= 1'b0;
                start_after_load <= 1'b1;
            end

            if (rx_valid) begin
                case (rx_state)
                    R_SYNC0: rx_state <= (rx_data == "T") ? R_SYNC1 : R_SYNC0;
                    R_SYNC1: rx_state <= (rx_data == "N") ? R_CMD : R_SYNC0;
                    R_CMD: begin
                        command <= rx_data;
                        payload_count <= 7'd0;
                        if (rx_data == "S") begin
                            core_stop <= 1'b1;
                            rx_state <= R_SYNC0;
                        end else if (rx_data == "H") begin
                            midstate <= 256'hbc909a336358bff090ccac7d1e59caa8c3c8d8e94f0103c896b187364719f91b;
                            tail <= 96'h4b1e5e4a29ab5f49ffff001d;
                            target <= 256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
                            start_pending <= 1'b1;
                            rx_state <= R_SYNC0;
                        end else if (rx_data == "J" || rx_data == "E") begin
                            if (rx_data == "J") begin
                                flush_results <= 1'b1;
                            end
                            rx_state <= R_PAYLOAD;
                        end else begin
                            rx_state <= R_SYNC0;
                        end
                    end
                    R_PAYLOAD: begin
                        if (payload_count < 7'd32) begin
                            midstate <= {midstate[247:0], rx_data};
                        end else if (payload_count < 7'd44) begin
                            tail <= {tail[87:0], rx_data};
                        end else begin
                            target <= {target[247:0], rx_data};
                        end

                        if (payload_count == JOB_BYTES - 1) begin
                            if (command == "J") begin
                                start_pending <= 1'b1;
                            end else begin
                                echo_toggle <= ~echo_toggle;
                            end
                            rx_state <= R_SYNC0;
                        end else begin
                            payload_count <= payload_count + 7'd1;
                        end
                    end
                    default: rx_state <= R_SYNC0;
                endcase
            end
        end
    end

    reg [287:0] tx_payload = 288'd0;

    localparam T_IDLE = 3'd0;
    localparam T_FETCH = 3'd1;
    localparam T_LOAD = 3'd2;
    localparam T_SEND = 3'd3;
    localparam T_WAIT = 3'd4;
    reg [2:0] tx_state = T_IDLE;
    reg [6:0] tx_index = 7'd0;
    reg echo_seen_toggle = 1'b0;
    reg tx_echo = 1'b0;
    reg [CORE_INDEX_BITS-1:0] active_fifo = {CORE_INDEX_BITS{1'b0}};
    reg fifo_available;
    reg [CORE_INDEX_BITS-1:0] selected_fifo;
    integer fifo_select_index;

    always @(*) begin
        fifo_available = 1'b0;
        selected_fifo = {CORE_INDEX_BITS{1'b0}};
        for (fifo_select_index = 0; fifo_select_index < CORES;
             fifo_select_index = fifo_select_index + 1) begin
            if (!fifo_empty[fifo_select_index] && !fifo_available) begin
                fifo_available = 1'b1;
                selected_fifo = fifo_select_index[CORE_INDEX_BITS-1:0];
            end
        end
    end

    function [7:0] echo_response_byte;
        input [6:0] index;
        begin
            if (index == 0) begin
                echo_response_byte = "E";
            end else if (index <= 32) begin
                echo_response_byte = midstate[255 - (index - 1) * 8 -: 8];
            end else if (index <= 44) begin
                echo_response_byte = tail[95 - (index - 33) * 8 -: 8];
            end else begin
                echo_response_byte = target[255 - (index - 45) * 8 -: 8];
            end
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            tx_start <= 1'b0;
            tx_state <= T_IDLE;
            tx_index <= 7'd0;
            echo_seen_toggle <= 1'b0;
            tx_echo <= 1'b0;
            fifo_pop <= {CORES{1'b0}};
        end else if (flush_results) begin
            tx_start <= 1'b0;
            tx_state <= T_IDLE;
            tx_index <= 7'd0;
            fifo_pop <= {CORES{1'b0}};
        end else begin
            tx_start <= 1'b0;
            fifo_pop <= {CORES{1'b0}};
            case (tx_state)
                T_IDLE: begin
                    if (echo_seen_toggle != echo_toggle) begin
                        tx_echo <= 1'b1;
                        tx_index <= 7'd0;
                        echo_seen_toggle <= echo_toggle;
                        tx_state <= T_SEND;
                    end else if (fifo_available) begin
                        tx_echo <= 1'b0;
                        active_fifo <= selected_fifo;
                        fifo_pop[selected_fifo] <= 1'b1;
                        tx_state <= T_FETCH;
                    end
                end
                T_FETCH: tx_state <= T_LOAD;
                T_LOAD: begin
                    tx_payload <= fifo_pop_data[active_fifo*288 +: 288];
                    tx_index <= 7'd0;
                    tx_state <= T_SEND;
                end
                T_SEND: begin
                    if (!tx_busy) begin
                        if (tx_echo) begin
                            tx_data <= echo_response_byte(tx_index);
                        end else if (tx_index == 0) begin
                            tx_data <= "F";
                        end else begin
                            tx_data <= tx_payload[287 - (tx_index - 1) * 8 -: 8];
                        end
                        tx_start <= 1'b1;
                        tx_state <= T_WAIT;
                    end
                end
                T_WAIT: begin
                    if (tx_busy) begin
                        if ((tx_echo && tx_index == ECHO_RESP_BYTES - 1) ||
                            (!tx_echo && tx_index == FOUND_RESP_BYTES - 1)) begin
                            tx_state <= T_IDLE;
                        end else begin
                            tx_index <= tx_index + 7'd1;
                            tx_state <= T_SEND;
                        end
                    end
                end
                default: tx_state <= T_IDLE;
            endcase
        end
    end

    assign led[0] = ~(|core_running);
    assign led[1] = ~(|core_found);
    assign led[2] = ~(|fifo_overflow);

    genvar led_index;
    generate
        for (led_index = 3; led_index < LEDS; led_index = led_index + 1) begin : status_leds
            assign led[led_index] = ~core_current_nonce[16 + led_index];
        end
    endgenerate
endmodule
`default_nettype wire
