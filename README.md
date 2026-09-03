# 3D Graphics Renderer

An FPGA-based 3D triangle renderer written in SystemVerilog. The design draws a rotating cube and two pyramids on a 640 x 480 VGA display without a CPU, GPU, or graphics library.

<!-- Add the main VGA output photo or demo GIF here after publishing. -->


## Features

- 64-entry ready/valid queue for 3D triangle commands
- Signed Q8.8 vertex coordinates
- Y-axis model rotation and a fixed camera pitch
- Fixed-point perspective projection using `1/z`
- Geometric near-plane and screen-edge clipping
- Backface culling
- Edge-equation triangle rasterization
- On-chip 8-bit inverse-Z buffer
- Two on-chip color buffers for tear-free page flipping
- 256-entry RGB color palette
- 320 x 240 internal rendering scaled to 640 x 480 VGA
- On-screen FPS counter
- Demo scene made from 24 triangles

## Architecture

```text
Triangle input
      |
64-entry FIFO
      |
3D rotation and camera transform
      |
Near-plane clipping
      |
Perspective projection using 1/z
      |
Viewport clipping and backface culling
      |
Edge-equation rasterizer and Z test
      |
Indexed back buffer
      |
Palette lookup and double-buffered VGA output
```

Each command contains three 3D vertices and one 8-bit color index. The transform stage rotates the vertices, applies the camera view, and clips geometry before and after projection. Clipped polygons are split back into triangles before rasterization.

The rasterizer steps through each triangle's bounding box. Edge equations find covered pixels, while reciprocal depth is interpolated across the triangle. A pixel is written only when its depth is closer than the value in the Z buffer.

<!-- Add a renderer pipeline diagram here after publishing. -->


## Memory

- Color page 0: 320 x 240 x 8 bits
- Color page 1: 320 x 240 x 8 bits
- Z buffer: 320 x 240 x 8 bits
- Render memory: 1,843,200 bits

The color pages and Z buffer use Intel `altsyncram` M9K block RAM. Quartus reports 1,855,424 total memory bits, including the palette and other inferred storage.

## Hardware

The project targets the Terasic DE2-115 board and its Intel Cyclone IV E `EP4CE115F29C7` FPGA. Rendering runs at 50 MHz. VGA output runs at 25 MHz through the board's video DAC.

The current build uses 6,430 logic elements, 2,581 registers, 1,855,424 memory bits, and 54 embedded 9-bit multiplier elements.

<!-- Add a photo of the DE2-115 and VGA setup here after publishing. -->


## Controls

- `KEY[0]`: active-low reset
- `KEY[1]`: restart the animation

## Project Layout

- `rtl/common`: shared types and fixed-point divider
- `rtl/pipeline`: triangle queue, transform stage, clipping, and rasterizer
- `rtl/memory`: framebuffer, Z-buffer, and palette RAM
- `rtl/video`: VGA timing and display controller
- `rtl/demo`: top-level design and demo scene
- `sim`: ModelSim testbenches

## Building

1. Open `Graphics.qpf` in Intel Quartus Prime 18.1.
2. Compile the project.
3. Program `output_files/Graphics.sof` onto the DE2-115.
4. Connect a VGA display and release `KEY[0]`.

## Simulation

The `sim` folder contains testbenches for the triangle queue, transform and clipping stages, rasterizer, VGA timing, double buffering, and demo scene.

