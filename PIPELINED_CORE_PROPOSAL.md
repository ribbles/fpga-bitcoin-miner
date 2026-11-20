# Fully Pipelined Bitcoin SHA-256 Core Proposal for Kintex UltraScale+

## Executive summary

Replace every iterative `bitcoin_hash_core` with an independent, spatially unrolled, feed-forward double-SHA-256 pipeline that accepts one nonce every clock and produces one final hash every clock after the pipeline fills. Preserve the existing job and result protocol and keep `CORES` as the number of physically instantiated pipelines; the implemented XCKU5P build contains three complete pipelines.

The hardware-verified three-core build runs at **100 MHz**, with post-route setup slack of **+4.207 ns** and hold slack of **+0.010 ns**. It provides approximately **300 MH/s aggregate throughput** on the physical board; the earlier 200 MHz route passed static timing but did not mine reliably on hardware.

At one accepted nonce per cycle per core, three 100 MHz cores produce approximately 300 MH/s. This is roughly three times the estimated aggregate throughput of the current 64-core, 200 MHz iterative build.

## Existing design baseline

The repository currently has:

- `bitcoin_hash_core.sv`, which uses one iterative compressor twice for every nonce.
- `sha256_compress.sv`, which performs one SHA-256 round per cycle and needs 64 cycles per block.
- Additional start/done and transition cycles, making a nonce cost approximately 130-132 cycles per current core.
- A post-synthesis 64-core XCKU5P build using 122,986 LUTs (56.69%), 207,615 FFs (47.85%), no BRAM/URAM/DSP, and meeting 199.94 MHz with 0.222 ns WNS.

The current architecture therefore obtains approximately:

```text
hash rate ~= physical iterative cores * clock / 130
          ~= 64 * 199.94 MHz / 130
          ~= 98.4 MH/s
```

The proposed pipeline obtains:

```text
hash rate = CORES * clock
          = 3 * 100 MHz
          = 300 MH/s
```

## Proposed architecture

### Datapath

Use two consecutive, fully unrolled compression pipelines:

```text
per-core nonce counter
    -> SHA-256 compression 1, rounds 0..63, seeded by job midstate
    -> SHA-256 compression 2, rounds 0..63, seeded by SHA-256 IV
    -> byte-order conversion and staged target comparison
    -> result FIFO / existing report interface
```

Compression 1 forms the second Bitcoin header block from the registered job tail, candidate nonce, padding, and fixed 640-bit message length. Compression 2 hashes the 256-bit first digest plus fixed SHA-256 padding and the 256-bit message length. There is no feedback from one nonce to the next; after fill, all stages operate on different nonces concurrently.

Each nonce, a valid bit, and a small job generation/tag travel beside the hash state so a stale result can be discarded immediately after `stop` or a new job. The entire 256-bit final hash should be retained only for a winning result; the normal path only needs the pipelined comparator state.

### Round microarchitecture

The implemented baseline uses one registered stage for every SHA-256 round in each of the two compressors. It has an initiation interval of one clock and uses compile-time round constants and fixed padding; additional intra-round register cuts remain a possible frequency experiment but are not part of the verified build.

Important implementation details:

- Express multi-operand sums so Vivado can use LUT6/CARRY8 chains efficiently; inspect the mapped netlist rather than assuming RTL addition order is optimal.
- Make every round constant `K[t]` a local constant at elaboration, eliminating the current 64-way constant mux.
- Constant-fold padding and fixed message words separately for the first and second compression pipelines.
- Propagate only the 16-word sliding message-schedule window needed by each round.
- Register the job midstate/tail locally at the head of every physical pipeline.
- Use a pipelined 256-bit less-than comparator, for example eight 32-bit compare slices with registered prefix-equal/less state, rather than one wide combinational comparison.
- Avoid high-fanout clock enables and resets in the datapath. Use a valid shift pipeline and job-generation tags; initialize or reset only control state.
- Keep nonce addition local to the pipeline input and use a free-running counter while enabled.

### Core count

The current `CORES` parameter means replicated engines and will retain that meaning. Every generated `bitcoin_hash_core` contains its own complete two-compression pipeline:

```systemverilog
parameter int CORES = 3; // physical fully pipelined cores
```

`CORES` supports 2 through 32+ at elaboration and preserves the existing partition rule:

```text
nonce(core, sequence) = START_NONCE + core + sequence * CORES
```

There is no shared hash pipeline or round-robin allocator: increasing `CORES` increases throughput linearly and also replicates the full datapath. Values above the capacity of the selected FPGA remain useful for larger devices, multiple FPGA partitions, and synthesis experiments, but 32 fully unrolled cores will not fit on an XCKU5P.

## Interfaces

### Drop-in compatibility interface

Retain the current externally visible signals and meanings:

```systemverilog
module bitcoin_hash_core #(
    parameter logic [31:0] START_NONCE  = 32'd0,
    parameter logic [31:0] NONCE_STRIDE = 32'd1
) (
    input  logic         clk,
    input  logic         start,
    input  logic         stop,
    input  logic [255:0] midstate,
    input  logic [95:0]  tail,
    input  logic [255:0] target,
    output logic         running,
    output logic         found,
    output logic [31:0]  found_nonce,
    output logic [255:0] found_hash,
    output logic [31:0]  current_nonce,
    output logic         result_valid,
    output logic [31:0]  result_nonce,
    output logic [255:0] result_hash,
    output logic [7:0]   report_byte_out,
    input  logic         report_load,
    input  logic         report_shift,
    input  logic         report_select,
    input  logic [8:0]   report_bit_index,
    output logic         report_bit_out
);
```

Compatibility behavior:

- `start` atomically captures `midstate`, `tail`, and `target`, advances the job generation, and begins injecting nonces.
- `stop` stops new injection immediately; in-flight entries become invalid through their generation tags.
- `running` means the input is accepting candidates, not that the long pipeline is empty.
- `found` and report data stay stable until restart, matching current behavior.
- `current_nonce` reports the most recently issued nonce rather than the nonce presently at the pipeline output.

### Preferred internal streaming interface

The implementation should internally use ready/valid records even if the compatibility wrapper never applies backpressure:

```systemverilog
job_valid/job_ready: {job_id, midstate, tail, target, start_nonce, nonce_stride}
hash_valid:          {job_id, nonce, final_hash}
result_valid:        {job_id, nonce, final_hash}
```

The main datapath remains stall-free. A small result FIFO decouples rare winning hashes from UART serialization; overflow should set a sticky error flag rather than stall hundreds of pipeline stages.

## Timing and maximum clock speed

### Device limit

The selected part is `xcku5p-ffvb676-1-i`. AMD DS922 specifies 667 MHz as the maximum global clock tree frequency for a -1 Kintex UltraScale+ at the normal 0.85 V operating point. Therefore a 1 GHz fabric/global clock is outside the device specification even if an isolated logic path appeared to route at that period.

### Expected implementation result

| Configuration | Verified post-route Fmax | Aggregate throughput | Status |
|---|---:|---:|---|
| Three cores, one stage per round | 100 MHz | 300 MH/s | Routed, hardware tested, normal miner verified |
| Earlier static-timing result | 200 MHz | 600 MH/s theoretical | Routed but failed physical mining tests |
| Device clock-network ceiling | 667 MHz | Not an achievable SHA guarantee | Specification boundary only |

The 100 MHz result passed full place-and-route, DRC, deterministic hardware proof-of-work, and normal pool-miner tests at approximately 297-299 MH/s. Static timing alone was insufficient to qualify the 200 MHz image, so 100 MHz is the release default.

The existing 700 MHz differential input may remain the reference because the MMCM input limit is 800 MHz for the -1 part, but the generated mining clock must remain within both the MMCM and 667 MHz global-clock limits.

## Resource estimate and maximum core count

The following results are from Vivado synthesis of the implemented complete design, including UART and result buffering.

| Resource | XCKU5P available | One-core build | Three-core build |
|---|---:|---:|---:|
| CLB LUTs | 216,960 | 51,365 (23.67%) | 151,903 (70.01%) |
| FFs | 433,920 | 49,984 (11.52%) | 144,196 (33.23%) |
| BRAM36 | 480 | 4 | 12 |
| UltraRAM | 64 | 0 | 0 |
| DSP48E2 | 1,824 | 0 | 0 |

Add approximately 2,000-6,000 LUTs and 2,000-8,000 FFs for UART, job distribution, result FIFO, clock/reset control, and duplicated regional control registers. The target comparator can reduce average logic by checking high-order target words first, but it must remain functionally equivalent to a full unsigned 256-bit comparison.

Conclusions for core count:

- **Physical fully pipelined cores on XCKU5P-1:** **three are hardware-verified** at 100 MHz, using about 70% of CLB LUTs.
- **Four cores:** linear synthesis scaling suggests about 94% LUT utilization before extra routing overhead, so it is not a practical timing-safe target on this device.
- **RTL configurability:** `CORES=2..32+` directly instantiates that many independent pipelines; the upper values require a substantially larger FPGA or multiple devices.
- **Thirty-two physical, fully unrolled engines:** not feasible on XCKU5P. Even optimistic estimates exceed device LUT capacity by well over an order of magnitude.
- **Existing iterative engines:** the current synthesis result is about 1,900 LUTs and 3,220 FFs per engine. Pure arithmetic suggests roughly 110 could consume the LUTs, but routing, controls, and timing make approximately 64-80 a more realistic ceiling for the current style.

The measured one-core and three-core builds replace the earlier area estimates.

## Floorplanning and implementation strategy

Lay out the 128 rounds as a folded serpentine pipeline across adjacent clock regions, with round order following physical placement. Keep each round's state and message-schedule registers beside its CARRY8/LUT logic. Place the first and second compression halves in separate rectangular pblocks and put the comparison/result logic at the output edge.

Recommended Vivado flow:

- Preserve useful round hierarchy during early floorplanning, then compare with rebuilt hierarchy.
- Use out-of-context synthesis for one round and one compressor to measure resource/timing scaling quickly.
- Apply pblocks by groups of 8 or 16 rounds, not 128 individually.
- Replicate job constants and valid/job-tag control at clock-region boundaries to prevent global high-fanout data nets.
- Use `phys_opt_design` register replication and critical-cell optimization, but verify functionality is not relying on unsafe multicycle exceptions.
- Run several placement seeds/directives and report the worst thermal/voltage timing corner for the industrial -1 device.
- Treat any path exception as an interface contract with a proof; the hashing pipeline itself should use ordinary single-cycle constraints.

## DDR4

DDR4 will not speed up SHA-256 hashing. Mining reuses one small job record for millions or billions of locally generated nonces, while every SHA round needs tightly coupled state every clock. Moving round state or message schedules through DDR would add latency, consume power, and provide far less useful random-access bandwidth than local registers.

DDR4 can still be useful outside the hot path for:

- Queuing many future jobs or version/time/extra-nonce variants.
- Buffering diagnostics, traces, counters, or rare share results.
- Supporting a host DMA interface if UART is later replaced.

It should not store per-nonce intermediate hashes, schedules, or pipeline state. BRAM is also unnecessary for the primary datapath because a register pipeline gives tighter timing and sufficient capacity.

## Verification plan

1. Retain the existing known-answer tests and run them against both old and new cores.
2. Add cycle-accurate tests that inject consecutive nonces every clock and check every output after the documented latency.
3. Randomize midstate, tail, target, start, and stop; compare all valid outputs with a software double-SHA-256 reference.
4. Verify byte order at the first block, second block, target comparator, and report interface independently.
5. Verify wraparound and coverage for every `CORES` value from 2 through 32, including non-powers of two.
6. Prove that cores never duplicate or omit a nonce over a bounded interval.
7. Verify that a stopped/replaced job cannot report a stale in-flight result.
8. Run post-synthesis and post-route timing simulation only for clock/reset/interface risks; use RTL/formal equivalence for the high-volume datapath checks.
9. Measure on-board power, junction temperature, and error-free runtime before increasing beyond 500 MHz.

## Delivery stages

### Stage 1: architecture proof (complete)

Implemented and verified the unrolled compressor and known-answer test; full implementation results show that 200 MHz is the appropriate three-core target.

### Stage 2: complete engine (complete)

Connect the two compression pipelines, nonce/tag transport, target comparator, generation-based flush, and compatibility wrapper. Confirm one result per cycle after fill.

### Stage 3: integration (complete)

Added `top_pipelined.sv` with three independent cores, existing UART modules, unchanged wire protocol, per-core result queues, and a separate UltraScale+ build target.

### Stage 4: closure and tuning (initial closure complete)

The unrestricted build routes cleanly at 200 MHz. Pblocks informed by the captured placement, alternative directives/seeds, and on-board power/temperature measurements remain future tuning work.

## Risks

- **Area headroom:** the measured three-core design uses 70.01% of CLB LUTs, leaving limited room for further replication or unrelated logic.
- **Routing, not logic:** 128 wide state/schedule boundaries can exhaust local routing and lower Fmax well before LUT capacity is exhausted.
- **Clock specification:** 1 GHz is prohibited by the -1 device's global clock specification; even 650 MHz leaves almost no clock-network margin.
- **Power and thermal load:** toggling most of a large pipeline every cycle can exceed the board's cooling or regulator margin even when timing closes.
- **High fanout:** job data, valid/stop, target, and reset can become critical global nets unless registered and replicated locally.
- **Byte order errors:** Bitcoin header, SHA digest, target, and serial report conventions use different apparent byte orders.
- **Stale results:** the pipeline cannot be physically emptied instantly; job-generation tagging is required when jobs change.
- **Compatibility semantics:** `current_nonce`, `running`, and stop latency differ naturally from an iterative core and must be defined at the wrapper.
- **Tool variability:** placement seed, Vivado version, hierarchy settings, and pblock choices may change Fmax substantially.
- **Result backpressure:** a stallable 256+ stage datapath is expensive; rare result bursts need buffering or explicit overflow behavior.

## Assumptions

- The target remains `xcku5p-ffvb676-1-i` at the normal 0.85 V VCCINT setting shown in the current build.
- “100% pipelined” means initiation interval 1: every core accepts one new nonce and, after fill, produces one final hash per clock.
- `CORES=2..32+` represents physically replicated, independent, fully unrolled pipelines.
- Jobs provide the SHA-256 midstate after the first 64-byte Bitcoin header block, the remaining 12 bytes, and a full 256-bit target, as in the current interface.
- The existing UART wire protocol and found-result payload must remain unchanged.
- SHA arithmetic remains in LUT/CARRY8 fabric; DSPs do not provide a useful advantage for rotates, boolean functions, and 32-bit modular additions.
- Exact resource use and Fmax cannot be guaranteed until the new RTL is synthesized, placed, and routed.
- Mining-clock reliability will be validated at operating temperature, not only with a cold-board timing report.

## Questions

These do not block the proposed first implementation, but should be resolved before final interface freeze:

1. Should the two-core XCKU5P build prioritize maximum aggregate hash rate or maximum clock frequency when those goals select different round-pipeline depths?
   - max hash rate
2. Is the preferred optimization target maximum total MH/s, maximum MH/s/W, or the highest demonstrable clock frequency?
   - max hash rate
3. What cooling, VCCINT regulator current, and board power limits are available for sustained operation?
   - no idea. It's got a fan.
4. Must the design remain portable to Kintex-7 and Gowin targets, or may the new pipeline be selected only for UltraScale+?
   - just ultrascale+. If it can be run on Kintex7 then bonus
5. Is a small change to `top.sv` acceptable so one shared cluster replaces the current generate-loop of independent cores?
   - dont use it, since we only have one core we should create top_pipelined.sv
6. Should multiple simultaneous winning hashes be queued, or is keeping only the first winner per job sufficient?
   - queued
7. What timing margin and Vivado seed policy is required for a release build?
   - at your discretion

## References and evidence

- Local baseline: `build_vivado/utilization_synth.rpt`, `build_vivado/utilization_synth_hier.rpt`, and `build_vivado/post_route_timing_summary.txt` from the current 64-core build.
- AMD, *Kintex UltraScale+ FPGAs Data Sheet: DC and AC Switching Characteristics (DS922)*, clock-buffer and MMCM switching characteristics: <https://docs.amd.com/r/en-US/ds922-kintex-ultrascale-plus/Clock-Buffers-and-Networks>.
- AMD, *UltraScale Architecture and Product Data Sheet: Overview (DS890)* for XCKU5P device resources: <https://docs.amd.com/api/khub/documents/dGU6Y~1b8XPqDFk5ulti6g/content>.
