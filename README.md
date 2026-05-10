# ZPIC CUDA + MPI Optimizations on Deucalion

![Language](https://img.shields.io/badge/language-C%20%7C%20CUDA-blue)
![Parallelism](https://img.shields.io/badge/parallelism-OpenMP%20%7C%20MPI%20%7C%20CUDA-orange)
![Platform](https://img.shields.io/badge/platform-Deucalion%20HPC-purple)
![Grade](https://img.shields.io/badge/grade-18%2F20-brightgreen)

This repository contains an optimized version of **ZPIC**, an educational Particle-In-Cell (PIC) plasma simulation code, adapted and evaluated on the heterogeneous architectures available on the **Deucalion supercomputer**.

The project explores how different parallel programming models and hardware architectures affect the performance of PIC simulations, focusing on:

- **OpenMP** shared-memory parallelism on CPU nodes;
- **MPI + OpenMP** hybrid distributed-memory execution;
- **CUDA** acceleration on NVIDIA A100 GPUs;
- architecture-aware optimization for **Fujitsu A64FX**, **AMD EPYC 7742**, and **NVIDIA A100**.

> **Academic grade:** `18/20`

---

## Project Context

Particle-In-Cell simulations model the interaction between charged particles and electromagnetic fields. Although the method exposes a high degree of parallelism, performance is often limited by irregular memory accesses, particle deposition, stencil-based field updates, memory bandwidth, and communication overheads.

This project evaluates ZPIC using two representative simulation configurations:

| Work Assignment | Simulation | Main Characteristic | Dominant Bottleneck |
|---|---|---|---|
| WA1 | Laser-particle simulation | Large grid, low particles per cell | Grid-based kernels, current smoothing, Maxwell solver |
| WA2 | Two-stream instability | Small grid, high particles per cell | Particle pusher, `spec_advance()` |

The work was developed for the **Parallel Computing** course at the **University of Minho**.

---

## Authors

- **Diogo Coelho da Silva**  
  University of Minho  
  `pg61444@alunos.uminho.pt`

- **Tomás Alexandre Torres Pereira**  
  University of Minho  
  `pg59810@alunos.uminho.pt`

---

## Repository Structure

```text
.
├── build/              # Build artifacts
├── lib/                # Header files and common library code
├── src/                # ZPIC source code and CUDA implementation
├── tests/              # Test outputs, logs, benchmark results
├── CPAR_FINAL.pdf      # Final project report
├── Makefile            # CUDA-oriented build system
├── compile.sh          # SLURM compilation script
├── gpu.sh              # SLURM GPU execution script
├── zpic                # Generated executable, if already built
└── README.md
```

---

## Main Optimizations

### 1. Data-layout transformation for A64FX

The original ZPIC code uses several **Array of Structures** layouts, such as `Float3` and `Particle`. These layouts limit SIMD vectorization because fields are interleaved in memory.

To improve vectorization, selected data structures were reorganized into a **Structure of Arrays** layout, exposing contiguous memory streams for each field.

Additional memory alignment was introduced using **256-byte aligned allocation**, matching the cache-line characteristics of the Fujitsu A64FX memory hierarchy.

### 2. SVE vectorization

The Fujitsu A64FX supports **Arm Scalable Vector Extension** instructions. The project evaluates the effect of enabling SVE-friendly code generation and data access patterns.

Single-core performance improved from approximately:

```text
82.7 s  ->  39.4 s
```

This corresponds to a speedup of about:

```text
2.1x
```

### 3. OpenMP shared-memory parallelism

OpenMP was applied to the main particle loop and selected grid-based kernels.

For WA1, performance improved up to approximately one A64FX CMG, after which scalability degraded due to HBM2 bandwidth saturation and OpenMP overhead.

For WA2, the particle-dominated workload exposed more parallelism and scaled better across CPU cores.

### 4. Hybrid MPI + OpenMP

A hybrid MPI + OpenMP implementation was developed for the WA2 configuration.

The implementation uses a particle-based decomposition strategy:

1. particles are distributed across MPI ranks;
2. each rank advances its local particles;
3. OpenMP is used inside each rank;
4. current buffers and diagnostic values are combined using MPI collectives.

MPI rank placement was architecture-aware:

- **A64FX:** CMG-aligned placement;
- **AMD EPYC 7742:** CCD/NUMA-aware placement.

Although this enabled multi-node execution, scalability was limited by particle redistribution, global reductions, and synchronization at every timestep.

### 5. CUDA acceleration on NVIDIA A100

The CUDA implementation targets the dominant WA2 hotspot: `spec_advance()`.

Implemented GPU-side strategies include:

- CUDA kernel offloading of the particle pusher;
- asynchronous CUDA streams for computation and memory transfers;
- reduced host-device transfers where possible;
- global atomic current deposition;
- warp-level and block-level reductions for particle energy computation;
- evaluation of different CUDA thread-block sizes.

A block size of **256 threads** was selected as the baseline, because it provided strong occupancy and robust performance without relying on marginal gains from larger blocks.

---

## Build Instructions

### Requirements

The project assumes an HPC environment with:

- CUDA-capable compiler stack;
- NVIDIA GPU support for the CUDA version used by the system;
- C/C++ toolchain;
- SLURM, for batch execution on Deucalion;
- optional MPI and OpenMP support, depending on the branch/configuration being tested.

On Deucalion, the provided scripts load the CUDA module automatically.

---

## Compile

Using the Makefile directly:

```bash
make clean
make
```

Using the provided SLURM compilation script:

```bash
sbatch compile.sh
```

The generated executable is:

```text
zpic
```

---

## Run on GPU

Submit a standard GPU run:

```bash
sbatch gpu.sh run
```

Run with `perf stat` instrumentation:

```bash
sbatch gpu.sh perf_stat
```

The GPU script targets one NVIDIA A100 GPU and stores outputs under:

```text
tests/results/
tests/perf/
tests/slurm_logs/
```

---

## Performance Summary

### WA1: Laser-particle simulation

The WA1 workload uses a large grid with relatively few particles per cell. As a result, grid-based operations represent a substantial portion of the runtime.

Key observations:

- `spec_advance()` remains the largest hotspot;
- current smoothing and electromagnetic field updates are also relevant;
- SVE vectorization improves single-core performance significantly;
- OpenMP scaling improves up to around one A64FX CMG;
- beyond that point, HBM2 bandwidth saturation limits speedup.

Best reported WA1 result on A64FX:

```text
Maximum OpenMP speedup: 4.31x at 12 threads
```

---

### WA2: Two-stream instability

The WA2 workload has a smaller grid and a much larger particle count per cell. This shifts the dominant cost to the particle pusher.

Key observations:

- nearly 90% of execution time is concentrated in `spec_advance()`;
- WA2 exposes more parallelism than WA1;
- AMD EPYC 7742 achieves the lowest CPU execution time;
- A64FX remains competitive and energy-efficient at moderate thread counts;
- MPI scales poorly because communication dominates at scale;
- CUDA acceleration helps, but is limited by current-deposition atomics and host-device transfers.

---

## Best Cross-Architecture Results

| Architecture / Configuration | Best Runtime |
|---|---:|
| AMD EPYC 7742, OpenMP, 64 cores | `0.145 s` |
| Fujitsu A64FX, OpenMP, 48 threads | `0.494 s` |
| NVIDIA A100, CUDA, 256-thread blocks | `1.072 s` |
| Fujitsu A64FX, MPI, 2 ranks / 24 cores | `3.995 s` |
| AMD EPYC 7742, MPI, 1 rank / 16 cores | `4.110 s` |

The results show that the best implementation for the current ZPIC design is **shared-memory CPU parallelism**, especially on the AMD EPYC 7742 for the WA2 workload.

---

## Main Conclusions

The main conclusion of the project is that ZPIC performance is strongly workload-dependent.

For grid-dominated workloads, performance is constrained by memory bandwidth and low arithmetic intensity. For particle-dominated workloads, the application exposes more parallelism, but still suffers from memory irregularity, current-deposition contention, and synchronization overheads.

The most effective strategy for the current implementation is:

```text
Shared-memory OpenMP CPU execution
```

The least effective strategy, for the tested problem sizes, is:

```text
Hybrid MPI + OpenMP with full particle redistribution at every timestep
```

CUDA acceleration is promising, but the current implementation is limited because only the main hotspot was ported to the GPU. A fully GPU-resident implementation would likely reduce host-device transfer overhead and improve performance.

---

## Future Work

Possible extensions include:

- fully GPU-resident ZPIC implementation;
- particle sorting by cell to reduce current-deposition atomic contention;
- shared-memory or privatized deposition schemes on GPU;
- spatial domain decomposition instead of global particle redistribution;
- multi-GPU execution;
- improved MPI decomposition with halo exchanges;
- architecture-aware performance modelling;
- automated benchmark scripts for CPU/GPU comparison;
- integration with profiling tools such as Nsight Compute, Nsight Systems, LIKWID, or perf.

---

## Academic Report

The complete technical analysis is available in:

```text
CPAR_FINAL.pdf
```

Title:

```text
Evaluating different optimizations on ZPIC using heterogeneous architecture at Deucalion
```

---

## Citation

If you use or refer to this project, cite it as:

```bibtex
@misc{silva_pereira_zpic_deucalion_2026,
  title        = {Evaluating different optimizations on ZPIC using heterogeneous architecture at Deucalion},
  author       = {Diogo Coelho da Silva and Tomás Alexandre Torres Pereira},
  year         = {2026},
  institution  = {University of Minho},
  note         = {Parallel Computing project, grade: 18/20}
}
```

---

## License

No explicit license is currently provided in the repository. If this project is reused, please contact the authors or add an appropriate open-source license.
