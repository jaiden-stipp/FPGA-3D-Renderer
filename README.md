# 3D Graphics Renderer

An FPGA-based 3D triangle renderer written in SystemVerilog. The hardware draws 3D triangles on a 640 x 480 VGA display without a CPU or GPU. A C++ library builds custom scenes and command streams for the renderer.

<img width="2880" height="2160" alt="image" src="https://github.com/user-attachments/assets/6ea2d2a4-5762-437d-8988-672ec8d88c7b" />

<img width="2880" height="2160" alt="image" src="https://github.com/user-attachments/assets/375ede41-1f6e-4055-afef-77cd5e20ae13" />



## Features

- General ready/valid command interface for frame setup and triangle submission
- Versioned binary command stream with CRC error detection
- C++17 library for meshes, transforms, palettes, bulk uploads, and command generation
- Sixteen persistent indexed-mesh handles with on-chip vertex and index RAM
- Per-draw fixed-point 3 x 4 model matrices
- Reliable, sequenced UDP input through the DE2-115 ENET0 port
- Frame IDs, packet acknowledgements, FIFO-space reports, and display completion status
- Hardware ARP replies and a 2048-byte clock-crossing receive FIFO
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
C++ scene -> UDP receiver -> Binary decoder --+
                                               |
Built-in demo ---------------------------------+
                                               |
                                          Command mux
                                               |
                                          Command processor
                                                |
                                          Indexed mesh RAM and vertex fetch, or direct triangle
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

The ENET0 receiver answers ARP for a fixed IPv4 address, filters UDP packets, orders each submission's packets, and moves command bytes from the 25 MHz MII clock domain into the 50 MHz renderer domain. It acknowledges each packet with the submission ID, sequence number, result, and free FIFO space. The stream decoder checks each command's format and CRC before producing ready/valid graphics commands. Bulk mesh records are buffered in one M9K and replayed into the same command path used by the original single-record opcodes. The command processor handles palette updates, mesh uploads, frame clearing, direct triangles, indexed draws, draining, and page swaps. When a swap completes, the FPGA sends the displayed frame ID back to the computer. `SW[0]` selects Ethernet commands or the built-in demo.

Each draw command contains three 3D vertices and one 8-bit color index. The transform stage rotates the vertices, applies the camera view, and clips geometry before and after projection. Clipped polygons are split back into triangles before rasterization.

Indexed meshes can be uploaded once and reused. Each indexed draw fetches three vertices from on-chip RAM, applies its own Q8.8 3 x 4 model matrix, and sends the resulting triangle through the same graphics pipeline. Three shared multipliers process the matrix one row at a time instead of keeping nine multipliers active in parallel. The current fixed allocation supports 16 handles, 128 vertices per handle, and 256 triangles per handle.

The rasterizer steps through each triangle's bounding box. Edge equations find covered pixels, while reciprocal depth is interpolated across the triangle. A pixel is written only when its depth is closer than the value in the Z buffer.
## Memory

- Color page 0: 320 x 240 x 8 bits
- Color page 1: 320 x 240 x 8 bits
- Z buffer: 320 x 240 x 8 bits
- Render memory: 1,843,200 bits
- Indexed vertex store: 98,304 bits
- Indexed triangle store: 118,784 fitted bits

The color pages, Z buffer, vertex store, and triangle store use Intel `altsyncram` M9K block RAM. Quartus reports 2,094,584 total memory bits, including the palette, network FIFO, bulk upload buffer, and other inferred storage.

## Debugging Process
<img width="4032" height="3024" alt="image" src="https://github.com/user-attachments/assets/6147bdff-53cc-4008-98f4-3e645eb5851b" />
The full VGA path was working, and the FPGA could draw filled, colored triangles. However, the points were projected to the wrong screen positions. Some faces collapsed into thin lines, while others appeared far apart. Since the colors and triangle fills were correct, I focused on the 3D transform instead of the VGA controller. I used simple test triangles in ModelSim to check the signed Q8.8 math, camera offset, and 1/z projection one step at a time.
<img width="5712" height="4284" alt="image" src="https://github.com/user-attachments/assets/f095b4d8-7079-4d23-b135-0e644be3f71a" />
The scene was rendering, but parts of several frames appeared on the screen at the same time. The VGA controller was reading from the framebuffer while the rasterizer was still clearing and updating it, which caused visible screen tearing and incomplete shapes. I fixed this by adding double buffering. VGA displays one color buffer while the renderer draws the next frame into a second buffer. The buffers swap during vertical blanking, so only complete frames are shown.
<img width="5712" height="4284" alt="image" src="https://github.com/user-attachments/assets/b895ed0b-052d-4e86-b7b2-fdbfb43ba842" />
The vertices, projection, clipping, and depth testing were now working, but the cube looked as if it were being viewed from the inside. The backface-culling test was rejecting the front faces instead of the back faces. Screen projection reverses the Y axis, which also changes the winding direction of each triangle. Reversing the signed-area test fixed which faces were removed, while the Z-buffer handled the remaining overlap.

### Other Difficult Parts

Clipping was one of the hardest geometry problems. Rejecting every triangle that crossed the near plane made objects disappear as they approached the camera, while clamping projected vertices distorted triangles at the screen edges. The final pipeline computes fixed-point intersections with the near plane and viewport boundaries, builds the visible polygon, and splits it into replacement triangles. The generated vertices keep their reciprocal depth so the Z test remains correct after clipping.

The Z-buffer also required more than adding another RAM. Intel block RAM has registered read latency, so a pixel cannot be compared and written in one simple combinational step. The rasterizer now waits for the stored depth, compares it with the interpolated `1/z` value, and updates the depth and color memories only when the new pixel is closer. The clear, render, and display operations are sequenced so they do not compete for the same memory ports.

Inferring memories correctly was another hardware-specific challenge. The first vertex-fetch implementation used an asynchronous array read, which caused Quartus to expand the vertex store into about 179,000 logic cells instead of block RAM. The fetch stage was redesigned around synchronous read addresses, registered outputs, and explicit wait states. The bulk command decoder uses the same pattern, reading one buffered byte at a time instead of creating hundreds of parallel reads. Quartus maps these stores into M9K RAM, and the complete design fits in 11,276 logic elements while meeting 50 MHz timing.

Reliable Ethernet transfer required handling more than raw UDP reception. Large command streams are divided into numbered packets, moved from the 25 MHz MII clock domain into the 50 MHz renderer domain, checked for missing or duplicate sequences, and acknowledged with FIFO space and error flags. Submission IDs track packet delivery, while separate frame IDs confirm that a completed frame was actually swapped onto the VGA display. The C++ client retries lost packets and does not begin the next frame until display completion arrives.

Imported OBJ files created a different resource problem. The Suzanne model I tested has 2,012 vertices and 3,936 triangles, which originally required 23 mesh handles even though the FPGA provides 16. The software now centers and scales the model, groups nearby vertices, removes collapsed and duplicate faces, and divides the result into legal 128-vertex and 256-triangle chunks. Suzanne is reduced to 1,125 vertices and 2,274 triangles and fits into 14 handles, while small models are left unchanged.

## Hardware

The project targets the Terasic DE2-115 board and its Intel Cyclone IV E `EP4CE115F29C7` FPGA. Rendering runs at 50 MHz. A Cyclone IV PLL generates a 25.173611 MHz VGA pixel clock for a refresh rate of about 59.94 Hz.

The current build uses 11,336 logic elements, 5,487 registers, 2,094,584 memory bits, 264 M9K blocks, 60 embedded 9-bit multiplier elements, and one PLL. Its worst slow-corner setup slack is 1.709 ns, and every clock domain meets its setup and hold constraints.




## Controls

- `KEY[0]`: active-low reset
- `KEY[1]`: restart the animation
- `SW[0]` OFF: built-in rotating demo
- `SW[0]` ON: Ethernet command input
- `LEDG[0]`: Ethernet mode active
- `LEDG[1]`: 100 Mb/s link active
- `LEDG[2]`: UDP packet accepted
- `LEDG[3]`: network or command error

## Project Layout

- `rtl/common`: shared types and fixed-point divider
- `rtl/command`: graphics command decoding and frame control
- `rtl/system`: reusable command-to-VGA renderer core
- `rtl/network`: MII, ARP, UDP parsing, and clock-crossing FIFO
- `rtl/pipeline`: triangle queue, transform stage, clipping, and rasterizer
- `rtl/memory`: framebuffer, Z-buffer, and palette RAM
- `rtl/video`: VGA timing and display controller
- `rtl/demo`: top-level design and demo scene
- `sim`: ModelSim testbenches
- `software`: C++ library, tests, and example scene generator
- `docs`: protocol, setup, viewer, and implementation roadmap

## Building

1. Open `Graphics.qpf` in Intel Quartus Prime 18.1.
2. Compile the project.
3. Program `output_files/Graphics.sof` onto the DE2-115.
4. Connect a VGA display and release `KEY[0]`.

The default `SW[0]` OFF position runs the built-in demo. To test commands from a computer, follow [the Ethernet setup guide](docs/ethernet.md).

## Simulation

The `sim` folder contains testbenches for the command stream decoder, command processor, triangle queue, transform and clipping stages, rasterizer, VGA PLL and timing, double buffering, and demo scene.

## C++ Library

The library converts floating-point vertices to the renderer's signed Q8.8 format. It can apply translation, scale, and X, Y, or Z rotation to a mesh before encoding its triangles. It also generates palette and frame commands with the CRC expected by the FPGA decoder.

```cpp
fpga_renderer::CommandStream commands;
commands.setPalette(1, {255, 64, 32});
commands.setRotation(0);
commands.beginFrame(1);
commands.drawMesh(0, fpga_renderer::Mat4::scale(0.75F, 0.75F, 0.75F));
commands.endFrame();
fpga_renderer::RendererClient renderer("192.168.7.2");
renderer.uploadMesh(0, mesh);
const auto status = renderer.submit(commands);
```

Build and test it with:

```text
cmake -S . -B build
cmake --build build --config Release
ctest --test-dir build -C Release
```

Run `renderer_example` to generate a complete cube command stream. Run `renderer_udp_demo` to split and send that scene to `192.168.7.2:4000`, retry packets when needed, and wait for the displayed-frame response. `renderer_scene_tests` adds palette, depth, clipping, multi-packet stress, and orbit-animation tests for the VGA display. See [the command protocol](docs/command_protocol.md) and [the Ethernet setup guide](docs/ethernet.md) for the full path.

`renderer_model_viewer` loads Wavefront OBJ files, triangulates polygon faces, normalizes their size, and divides them across hardware mesh handles. It displays one to eight transformed instances, using one by default for large models and three for small models. Models that are too large are reduced with vertex clustering until they fit the 16-handle mesh store. See [the model viewer guide](docs/model_viewer.md).
