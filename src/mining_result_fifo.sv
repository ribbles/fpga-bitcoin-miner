`default_nettype wire

// One write port per mining core prevents simultaneous shares from being lost.
module mining_result_fifo #(
    parameter integer DEPTH = 256,
    parameter integer WIDTH = 288
) (
    input clk,
    input reset,
    input clear,
    input push,
    input [WIDTH-1:0] push_data,
    input pop,
    output reg [WIDTH-1:0] pop_data = {WIDTH{1'b0}},
    output empty,
    output full,
    output reg overflow = 1'b0
);
    localparam integer ADDR_BITS = $clog2(DEPTH);
    // The result queue is shallow and very wide. Distributed RAM avoids the
    // comparatively slow BRAM output path at the 600 MHz mining clock.
    (* ram_style = "distributed" *) reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_BITS-1:0] write_ptr = {ADDR_BITS{1'b0}};
    reg [ADDR_BITS-1:0] read_ptr = {ADDR_BITS{1'b0}};
    reg [ADDR_BITS:0] count = {(ADDR_BITS+1){1'b0}};
    reg empty_reg = 1'b1;
    reg full_reg = 1'b0;
    wire push_accept = push && (!full || pop);
    wire pop_accept = pop && !empty;

    assign empty = empty_reg;
    assign full = full_reg;

    always @(posedge clk) begin
        if (reset || clear) begin
            write_ptr <= {ADDR_BITS{1'b0}};
            read_ptr <= {ADDR_BITS{1'b0}};
            count <= {(ADDR_BITS+1){1'b0}};
            empty_reg <= 1'b1;
            full_reg <= 1'b0;
            overflow <= 1'b0;
        end else begin
            if (push_accept) begin
                memory[write_ptr] <= push_data;
                write_ptr <= write_ptr + {{(ADDR_BITS-1){1'b0}}, 1'b1};
            end else if (push) begin
                overflow <= 1'b1;
            end

            if (pop_accept) begin
                pop_data <= memory[read_ptr];
                read_ptr <= read_ptr + {{(ADDR_BITS-1){1'b0}}, 1'b1};
            end

            case ({push_accept, pop_accept})
                2'b10: begin
                    count <= count + 1'b1;
                    empty_reg <= 1'b0;
                    if (count == DEPTH - 1) begin
                        full_reg <= 1'b1;
                    end
                end
                2'b01: begin
                    count <= count - 1'b1;
                    full_reg <= 1'b0;
                    if (count == 1) begin
                        empty_reg <= 1'b1;
                    end
                end
                default: count <= count;
            endcase
        end
    end
endmodule
`default_nettype wire
