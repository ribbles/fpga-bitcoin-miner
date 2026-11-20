`default_nettype wire

// Fully unrolled SHA-256 compression pipeline. Each SHA round is split across
// three clocks so no stage contains the complete round addition chain. A new
// block is still accepted on every clock.
module sha256_compress_pipeline #(
    parameter integer TAG_WIDTH = 32
) (
    input clk,
    input valid_in,
    input [255:0] state_in,
    input [511:0] block_in,
    input [TAG_WIDTH-1:0] tag_in,
    output valid_out,
    output [255:0] state_out,
    output [TAG_WIDTH-1:0] tag_out
);
    function [31:0] rotr;
        input [31:0] x;
        input [4:0] n;
        begin
            rotr = (x >> n) | (x << (32 - n));
        end
    endfunction

    function [31:0] ch;
        input [31:0] x;
        input [31:0] y;
        input [31:0] z;
        begin
            ch = (x & y) ^ (~x & z);
        end
    endfunction

    function [31:0] maj;
        input [31:0] x;
        input [31:0] y;
        input [31:0] z;
        begin
            maj = (x & y) ^ (x & z) ^ (y & z);
        end
    endfunction

    function [31:0] bsig0;
        input [31:0] x;
        begin
            bsig0 = rotr(x, 5'd2) ^ rotr(x, 5'd13) ^ rotr(x, 5'd22);
        end
    endfunction

    function [31:0] bsig1;
        input [31:0] x;
        begin
            bsig1 = rotr(x, 5'd6) ^ rotr(x, 5'd11) ^ rotr(x, 5'd25);
        end
    endfunction

    function [31:0] ssig0;
        input [31:0] x;
        begin
            ssig0 = rotr(x, 5'd7) ^ rotr(x, 5'd18) ^ (x >> 3);
        end
    endfunction

    function [31:0] ssig1;
        input [31:0] x;
        begin
            ssig1 = rotr(x, 5'd17) ^ rotr(x, 5'd19) ^ (x >> 10);
        end
    endfunction

    function [31:0] round_k;
        input integer index;
        begin
            case (index)
                0: round_k = 32'h428a2f98;  1: round_k = 32'h71374491;
                2: round_k = 32'hb5c0fbcf;  3: round_k = 32'he9b5dba5;
                4: round_k = 32'h3956c25b;  5: round_k = 32'h59f111f1;
                6: round_k = 32'h923f82a4;  7: round_k = 32'hab1c5ed5;
                8: round_k = 32'hd807aa98;  9: round_k = 32'h12835b01;
                10: round_k = 32'h243185be; 11: round_k = 32'h550c7dc3;
                12: round_k = 32'h72be5d74; 13: round_k = 32'h80deb1fe;
                14: round_k = 32'h9bdc06a7; 15: round_k = 32'hc19bf174;
                16: round_k = 32'he49b69c1; 17: round_k = 32'hefbe4786;
                18: round_k = 32'h0fc19dc6; 19: round_k = 32'h240ca1cc;
                20: round_k = 32'h2de92c6f; 21: round_k = 32'h4a7484aa;
                22: round_k = 32'h5cb0a9dc; 23: round_k = 32'h76f988da;
                24: round_k = 32'h983e5152; 25: round_k = 32'ha831c66d;
                26: round_k = 32'hb00327c8; 27: round_k = 32'hbf597fc7;
                28: round_k = 32'hc6e00bf3; 29: round_k = 32'hd5a79147;
                30: round_k = 32'h06ca6351; 31: round_k = 32'h14292967;
                32: round_k = 32'h27b70a85; 33: round_k = 32'h2e1b2138;
                34: round_k = 32'h4d2c6dfc; 35: round_k = 32'h53380d13;
                36: round_k = 32'h650a7354; 37: round_k = 32'h766a0abb;
                38: round_k = 32'h81c2c92e; 39: round_k = 32'h92722c85;
                40: round_k = 32'ha2bfe8a1; 41: round_k = 32'ha81a664b;
                42: round_k = 32'hc24b8b70; 43: round_k = 32'hc76c51a3;
                44: round_k = 32'hd192e819; 45: round_k = 32'hd6990624;
                46: round_k = 32'hf40e3585; 47: round_k = 32'h106aa070;
                48: round_k = 32'h19a4c116; 49: round_k = 32'h1e376c08;
                50: round_k = 32'h2748774c; 51: round_k = 32'h34b0bcb5;
                52: round_k = 32'h391c0cb3; 53: round_k = 32'h4ed8aa4a;
                54: round_k = 32'h5b9cca4f; 55: round_k = 32'h682e6ff3;
                56: round_k = 32'h748f82ee; 57: round_k = 32'h78a5636f;
                58: round_k = 32'h84c87814; 59: round_k = 32'h8cc70208;
                60: round_k = 32'h90befffa; 61: round_k = 32'ha4506ceb;
                62: round_k = 32'hbef9a3f7; 63: round_k = 32'hc67178f2;
                default: round_k = 32'h00000000;
            endcase
        end
    endfunction

    reg valid_pipe [0:64];
    reg [TAG_WIDTH-1:0] tag_pipe [0:64];
    reg [255:0] base_pipe [0:64];
    reg [31:0] a_pipe [0:64];
    reg [31:0] b_pipe [0:64];
    reg [31:0] c_pipe [0:64];
    reg [31:0] d_pipe [0:64];
    reg [31:0] e_pipe [0:64];
    reg [31:0] f_pipe [0:64];
    reg [31:0] g_pipe [0:64];
    reg [31:0] h_pipe [0:64];
    reg [31:0] w_pipe [0:64][0:15];

    reg valid_s1 [0:63];
    reg [TAG_WIDTH-1:0] tag_s1 [0:63];
    reg [255:0] base_s1 [0:63];
    reg [31:0] a_s1 [0:63];
    reg [31:0] b_s1 [0:63];
    reg [31:0] c_s1 [0:63];
    reg [31:0] d_s1 [0:63];
    reg [31:0] e_s1 [0:63];
    reg [31:0] f_s1 [0:63];
    reg [31:0] g_s1 [0:63];
    reg [31:0] w_s1 [0:63][0:15];
    reg [31:0] temp1_sum_s1 [0:63];
    reg [31:0] temp1_carry_s1 [0:63];
    reg [31:0] temp2_s1 [0:63];
    reg [31:0] schedule_left_s1 [0:63];
    reg [31:0] schedule_right_s1 [0:63];

    reg valid_s2 [0:63];
    reg [TAG_WIDTH-1:0] tag_s2 [0:63];
    reg [255:0] base_s2 [0:63];
    reg [31:0] a_s2 [0:63];
    reg [31:0] b_s2 [0:63];
    reg [31:0] c_s2 [0:63];
    reg [31:0] d_s2 [0:63];
    reg [31:0] e_s2 [0:63];
    reg [31:0] f_s2 [0:63];
    reg [31:0] g_s2 [0:63];
    reg [31:0] w_s2 [0:63][0:15];
    reg [31:0] temp1_s2 [0:63];
    reg [31:0] temp2_s2 [0:63];
    reg [31:0] schedule_next_s2 [0:63];

    integer input_word;
    always @(posedge clk) begin
        valid_pipe[0] <= valid_in;
`ifdef PIPELINE_SIM_GATING
        if (valid_in) begin
`endif
        tag_pipe[0] <= tag_in;
        base_pipe[0] <= state_in;
        a_pipe[0] <= state_in[255:224];
        b_pipe[0] <= state_in[223:192];
        c_pipe[0] <= state_in[191:160];
        d_pipe[0] <= state_in[159:128];
        e_pipe[0] <= state_in[127:96];
        f_pipe[0] <= state_in[95:64];
        g_pipe[0] <= state_in[63:32];
        h_pipe[0] <= state_in[31:0];
        for (input_word = 0; input_word < 16; input_word = input_word + 1) begin
            w_pipe[0][input_word] <= block_in[511 - input_word * 32 -: 32];
        end
`ifdef PIPELINE_SIM_GATING
        end
`endif
    end

    genvar round_index;
    generate
        for (round_index = 0; round_index < 64; round_index = round_index + 1) begin : round_stage
            localparam [31:0] K = round_k(round_index);
            integer schedule_index;
            wire [31:0] choose_value =
                ch(e_pipe[round_index], f_pipe[round_index], g_pipe[round_index]);
            wire [31:0] sigma_value = bsig1(e_pipe[round_index]);
            wire [31:0] temp1_sum0 =
                h_pipe[round_index] ^ sigma_value ^ choose_value;
            wire [31:0] temp1_carry0 =
                ((h_pipe[round_index] & sigma_value) |
                 (h_pipe[round_index] & choose_value) |
                 (sigma_value & choose_value)) << 1;
            wire [31:0] temp1_sum1 =
                K ^ w_pipe[round_index][0] ^ temp1_sum0;
            wire [31:0] temp1_carry1 =
                ((K & w_pipe[round_index][0]) |
                 (K & temp1_sum0) |
                 (w_pipe[round_index][0] & temp1_sum0)) << 1;
            wire [31:0] temp1_sum_comb =
                temp1_sum1 ^ temp1_carry1 ^ temp1_carry0;
            wire [31:0] temp1_carry_comb =
                ((temp1_sum1 & temp1_carry1) |
                 (temp1_sum1 & temp1_carry0) |
                 (temp1_carry1 & temp1_carry0)) << 1;

            always @(posedge clk) begin
                valid_s1[round_index] <= valid_pipe[round_index];
`ifdef PIPELINE_SIM_GATING
                if (valid_pipe[round_index]) begin
`endif
                tag_s1[round_index] <= tag_pipe[round_index];
                base_s1[round_index] <= base_pipe[round_index];
                a_s1[round_index] <= a_pipe[round_index];
                b_s1[round_index] <= b_pipe[round_index];
                c_s1[round_index] <= c_pipe[round_index];
                d_s1[round_index] <= d_pipe[round_index];
                e_s1[round_index] <= e_pipe[round_index];
                f_s1[round_index] <= f_pipe[round_index];
                g_s1[round_index] <= g_pipe[round_index];
                // A three-level carry-save tree reduces all five T1 operands
                // without a carry chain; the only carry propagation is in S2.
                temp1_sum_s1[round_index] <= temp1_sum_comb;
                temp1_carry_s1[round_index] <= temp1_carry_comb;
                temp2_s1[round_index] <=
                    bsig0(a_pipe[round_index]) +
                    maj(a_pipe[round_index], b_pipe[round_index], c_pipe[round_index]);
                schedule_left_s1[round_index] <=
                    ssig1(w_pipe[round_index][14]) + w_pipe[round_index][9];
                schedule_right_s1[round_index] <=
                    ssig0(w_pipe[round_index][1]) + w_pipe[round_index][0];
                for (schedule_index = 0; schedule_index < 16; schedule_index = schedule_index + 1) begin
                    w_s1[round_index][schedule_index] <= w_pipe[round_index][schedule_index];
                end
`ifdef PIPELINE_SIM_GATING
                end
`endif
            end

            always @(posedge clk) begin
                valid_s2[round_index] <= valid_s1[round_index];
`ifdef PIPELINE_SIM_GATING
                if (valid_s1[round_index]) begin
`endif
                tag_s2[round_index] <= tag_s1[round_index];
                base_s2[round_index] <= base_s1[round_index];
                a_s2[round_index] <= a_s1[round_index];
                b_s2[round_index] <= b_s1[round_index];
                c_s2[round_index] <= c_s1[round_index];
                d_s2[round_index] <= d_s1[round_index];
                e_s2[round_index] <= e_s1[round_index];
                f_s2[round_index] <= f_s1[round_index];
                g_s2[round_index] <= g_s1[round_index];
                temp1_s2[round_index] <=
                    temp1_sum_s1[round_index] + temp1_carry_s1[round_index];
                temp2_s2[round_index] <= temp2_s1[round_index];
                schedule_next_s2[round_index] <=
                    schedule_left_s1[round_index] + schedule_right_s1[round_index];
                for (schedule_index = 0; schedule_index < 16; schedule_index = schedule_index + 1) begin
                    w_s2[round_index][schedule_index] <= w_s1[round_index][schedule_index];
                end
`ifdef PIPELINE_SIM_GATING
                end
`endif
            end

            always @(posedge clk) begin
                valid_pipe[round_index + 1] <= valid_s2[round_index];
`ifdef PIPELINE_SIM_GATING
                if (valid_s2[round_index]) begin
`endif
                tag_pipe[round_index + 1] <= tag_s2[round_index];
                base_pipe[round_index + 1] <= base_s2[round_index];
                a_pipe[round_index + 1] <= temp1_s2[round_index] + temp2_s2[round_index];
                b_pipe[round_index + 1] <= a_s2[round_index];
                c_pipe[round_index + 1] <= b_s2[round_index];
                d_pipe[round_index + 1] <= c_s2[round_index];
                e_pipe[round_index + 1] <= d_s2[round_index] + temp1_s2[round_index];
                f_pipe[round_index + 1] <= e_s2[round_index];
                g_pipe[round_index + 1] <= f_s2[round_index];
                h_pipe[round_index + 1] <= g_s2[round_index];
                for (schedule_index = 0; schedule_index < 15; schedule_index = schedule_index + 1) begin
                    w_pipe[round_index + 1][schedule_index] <= w_s2[round_index][schedule_index + 1];
                end
                w_pipe[round_index + 1][15] <= schedule_next_s2[round_index];
`ifdef PIPELINE_SIM_GATING
                end
`endif
            end
        end
    endgenerate

    reg valid_out_reg = 1'b0;
    reg [TAG_WIDTH-1:0] tag_out_reg = {TAG_WIDTH{1'b0}};
    reg [255:0] state_out_reg = 256'd0;

    // Isolate the feed-forward additions from the next compressor and target
    // comparator. This adds one cycle but does not change initiation interval.
    always @(posedge clk) begin
        valid_out_reg <= valid_pipe[64];
        tag_out_reg <= tag_pipe[64];
        state_out_reg <= {
            base_pipe[64][255:224] + a_pipe[64],
            base_pipe[64][223:192] + b_pipe[64],
            base_pipe[64][191:160] + c_pipe[64],
            base_pipe[64][159:128] + d_pipe[64],
            base_pipe[64][127:96]  + e_pipe[64],
            base_pipe[64][95:64]   + f_pipe[64],
            base_pipe[64][63:32]   + g_pipe[64],
            base_pipe[64][31:0]    + h_pipe[64]
        };
    end

    assign valid_out = valid_out_reg;
    assign tag_out = tag_out_reg;
    assign state_out = state_out_reg;
endmodule
