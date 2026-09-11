# Graphics Command Stream Protocol

The host sends a sequence of independently framed commands. An Ethernet receiver can pass each UDP payload to the decoder one byte at a time.

All multi-byte values are big-endian.

## Command Frame

| Field | Bytes | Value |
| --- | ---: | --- |
| Magic | 2 | `47 46` (`GF`) |
| Version | 1 | `02` |
| Opcode | 1 | Command type |
| Payload length | 1 | Number of payload bytes |
| Payload | 0-255 | Command data |
| CRC | 2 | CRC-16/CCITT-FALSE over every earlier byte in the frame |

The CRC starts at `FFFF` and uses polynomial `1021`. The decoder checks each command before forwarding it to the renderer. It can recover from lost or corrupt data by searching for the next `GF` magic value.

## Commands

| Opcode | Name | Payload |
| ---: | --- | --- |
| `01` | Begin frame | 32-bit frame ID |
| `02` | Draw triangle | Nine signed Q8.8 coordinates followed by one palette index |
| `03` | End frame | Empty |
| `04` | Set palette | Palette index, red, green, blue |
| `05` | Define mesh | Handle, vertex count, triangle count |
| `06` | Upload vertex | Handle, vertex number, signed Q8.8 X, Y, Z |
| `07` | Upload index | Handle, triangle number, three vertex indices, palette index |
| `08` | Draw mesh | Handle and a row-major Q8.8 3 x 4 model matrix |
| `09` | Upload vertices | Handle, first vertex number, count, then packed vertex records |
| `0A` | Upload indices | Handle, first triangle number, count, then packed index records |
| `0B` | Set view matrix | Row-major Q8.8 3 x 4 camera matrix |
| `0C` | Set projection | Focal X, focal Y, center X, center Y, and signed Q8.8 near Z |

`Begin frame` stores the frame ID and clears the back color buffer and Z-buffer. Draw commands then enter the ready/valid graphics pipeline. `End frame` waits for all triangles to finish and swaps buffers during vertical blanking. The same frame ID is returned in the displayed-frame UDP status packet.

The draw payload order is `x0, y0, z0, x1, y1, z1, x2, y2, z2, color`. Each coordinate uses two bytes. Values range from -128.0 through 127.99609375 in steps of 1/256.

## Indexed Mesh Commands

The mesh store provides 16 handles. Each handle reserves space for up to 128 vertices and 256 indexed triangles. Mesh upload commands are only valid between frames.

`Define mesh` has a five-byte payload: an 8-bit handle, a 16-bit vertex count, and a 16-bit triangle count. It must be sent before the vertex and index records for that handle.

`Upload vertex` has an eight-byte payload: handle, 8-bit vertex number, then signed Q8.8 X, Y, and Z values.

`Upload index` has a seven-byte payload: handle, 16-bit triangle number, three 8-bit vertex indices, and one palette index. Color remains flat per triangle.

The C++ library normally uses the two bulk upload commands to reduce command overhead. `Upload vertices` starts with a handle, an 8-bit first vertex number, and an 8-bit count. Each following record contains signed Q8.8 X, Y, and Z values, for six bytes per vertex. A frame holds at most 42 records because the command payload is limited to 255 bytes.

`Upload indices` starts with a handle, a 16-bit first triangle number, and an 8-bit count. Each four-byte record contains three vertex indices and one palette index. A frame holds at most 62 records. The decoder checks the CRC and the complete range before replaying either bulk command into the mesh store. The single-record opcodes remain supported for compatibility.

`Draw mesh` has a 25-byte payload. The first byte is the handle. The remaining 24 bytes contain twelve signed Q8.8 matrix values in row-major order:

```text
| m00 m01 m02 m03 |
| m10 m11 m12 m13 |
| m20 m21 m22 m23 |
```

For each indexed vertex `(x, y, z)`, the fetch stage calculates:

```text
x' = m00*x + m01*y + m02*z + m03
y' = m10*x + m11*y + m12*z + m13
z' = m20*x + m21*y + m22*z + m23
```

The transformed triangle then enters the view, clipping, perspective projection, rasterization, and Z-test pipeline. Results outside the signed Q8.8 coordinate range are saturated.

## Camera State

`Set view matrix` uses the same 24-byte matrix layout as `Draw mesh`. The matrix converts world coordinates to camera coordinates. Camera state may only change between frames and remains active until another command replaces it.

`Set projection` has a ten-byte payload containing five signed 16-bit values. Focal X and Y and center X and Y are pixel units. Near Z is Q8.8 camera-space depth. Projection computes `screen_x = center_x + focal_x*x/z` and `screen_y = center_y - focal_y*y/z`. The default is focal length 256, center `(160, 120)`, and near depth 2.0.

`protocol/protocol.json` is the canonical specification for versions, magic values, sizes, limits, opcodes, status events, and status flags. Run `scripts/generate_protocol.ps1` after changing it; generated SystemVerilog and C++ definitions must not be edited directly.
