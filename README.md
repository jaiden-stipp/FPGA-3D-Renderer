# 3D Graphics Renderer

An FPGA-based 3D triangle renderer written in SystemVerilog. The design draws 3 dimensional triangles on a 640 x 480 VGA display without a CPU, GPU, or graphics library.

<img width="5712" height="4284" alt="image" src="https://github.com/user-attachments/assets/97d45a35-ecdc-47d5-a79c-db0eb28f1308" />


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
## Memory

- Color page 0: 320 x 240 x 8 bits
- Color page 1: 320 x 240 x 8 bits
- Z buffer: 320 x 240 x 8 bits
- Render memory: 1,843,200 bits

The color pages and Z buffer use Intel `altsyncram` M9K block RAM. Quartus reports 1,855,424 total memory bits, including the palette and other inferred storage.

## Debugging Process
<img width="4032" height="3024" alt="image" src="https://github.com/user-attachments/assets/6147bdff-53cc-4008-98f4-3e645eb5851b" />
The full VGA path was working, and the FPGA could draw filled, colored triangles. However, the points were projected to the wrong screen positions. Some faces collapsed into thin lines, while others appeared far apart. Since the colors and triangle fills were correct, I focused on the 3D transform instead of the VGA controller. I used simple test triangles in ModelSim to check the signed Q8.8 math, camera offset, and 1/z projection one step at a time.
<img width="5712" height="4284" alt="image" src="https://github.com/user-attachments/assets/f095b4d8-7079-4d23-b135-0e644be3f71a" />
The scene was rendering, but parts of several frames appeared on the screen at the same time. The VGA controller was reading from the framebuffer while the rasterizer was still clearing and updating it, which caused visible screen tearing and incomplete shapes. I fixed this by adding double buffering. VGA displays one color buffer while the renderer draws the next frame into a second buffer. The buffers swap during vertical blanking, so only complete frames are shown.
<img width="5712" height="4284" alt="image" src="https://github.com/user-attachments/assets/b895ed0b-052d-4e86-b7b2-fdbfb43ba842" />
The vertices, projection, clipping, and depth testing were now working, but the cube looked as if it were being viewed from the inside. The backface-culling test was rejecting the front faces instead of the back faces. Screen projection reverses the Y axis, which also changes the winding direction of each triangle. Reversing the signed-area test fixed which faces were removed, while the Z-buffer handled the remaining overlap.

## Hardware

The project targets the Terasic DE2-115 board and its Intel Cyclone IV E `EP4CE115F29C7` FPGA. Rendering runs at 50 MHz. VGA output runs at 25 MHz

The current build uses 6,430 logic elements, 2,581 registers, 1,855,424 memory bits, and 54 embedded 9-bit multiplier elements.




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

