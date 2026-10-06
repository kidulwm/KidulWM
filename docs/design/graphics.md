# Graphics — the end design (production)

Status: DESIGN PROBE (Barticus 2026-10-06). Not-now, no code. Frozen here so the
rung exists when we reach production.

## The one law

KSD graphics is GPU-OPTIONAL. The face (kidulwm's UI) renders through a backend
chosen at boot, never a hard GPU dependency. A GPU is acceleration, not a
requirement. Same rule as every KSD machine-class decision: the flag is read
once at boot, never probed.

## Backends (the ladder)

  1. pixman (software) — the always-available floor. Proven on the VM today.
  2. GL (any hardware GPU) — i915 / AMD / pvr. Used when a GPU is present.

The face renders identically on both; the backend changes only throughput.

## Hybrid (iGPU + dGPU)

The display is physically wired to ONE GPU — the SCANOUT GPU (the iGPU by
default). The other is a RENDER-OFFLOAD target (PRIME offload): it renders,
then dma-buf / blits to the scanout GPU.

KSD's split is the face/payload seam:
  - iGPU = the FACE. kidulwm renders the UI here. Cheap, always free.
  - dGPU = the PAYLOAD. The brig's virtio-gpu (virgl/venus) renders here, and
           the AI brain computes here.

The brig already implies this: its virtio-gpu is host-GPU-backed. On a hybrid
host, that backing GPU is the dGPU, while the iGPU stays the face. Foreign code
renders on the expensive card; the UI stays on the cheap one.

## RISC-V — where does graphics come from

Grounded (Oct 2026):
  - SOME RISC-V SoCs ship a basic Imagination BXE iGPU (VisionFive 2 = BXE-4-32,
    SpacemiT K1 = BXE-2-32). The pvr Vulkan driver is open (Mesa 24.x) and does
    basic 3D; OpenGL via Zink. Young, not desktop-class.
  - Workstation-class boards often have NO iGPU (Milk-V Titan requires a
    discrete GPU over PCIe).
  - Discrete GPU on RISC-V is experimental: NVIDIA's CUDA-on-RISC-V port is
    done (demoed on SiFive BigSky + Blackwell, not shipped); ROCm/oneAPI
    experimental.

So graphics on RISC-V comes from the same ladder, lower rungs first:
  1. pixman (software) — the default. The face needs no GPU. This is KSD's
     floor, already proven.
  2. Imagination BXE iGPU — becomes the GL backend where a SoC has one and the
     pvr driver matures.
  3. Discrete GPU (Titan / BigSky class) — becomes the PAYLOAD GPU (the brain),
     once a runtime ships on RISC-V.

And the RISC-V brain may need NO GPU at all: the RVV (vector) + AME (matrix)
extensions do inference on-chip — the C950 runs a 27B-param model at ~30tps
using RVV+AME, no discrete GPU/NPU. So "the H200 box" becomes "a RISC-V vector
box": the accelerator is the ISA, not a card.

## The end design, in one line

The face is software-renderable by default; a GPU is a boot-time-selected
acceleration, and on hybrid hosts the split is iGPU=face / dGPU=payload. KSD
boots identically on x86-hybrid, RISC-V-bare, or ARM — the GPU is a rung you
climb, not a door you must unlock.
