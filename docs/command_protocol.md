# Graphics Command Stream Protocol

The host sends a sequence of independently framed commands. An Ethernet receiver can pass each UDP payload to the decoder one byte at a time.

All multi-byte values are big-endian.

## Command Frame

| Field | Bytes | Value |
| --- | ---: | --- |
| Magic | 2 | `47 46` (`GF`) |
| Version | 1 | `01` |
| Opcode | 1 | Command type |
| Payload length | 1 | Number of payload bytes |
| Payload | 0-255 | Command data |
| CRC | 2 | CRC-16/CCITT-FALSE over every earlier byte in the frame |

The CRC starts at `FFFF` and uses polynomial `1021`. The decoder checks each command before forwarding it to the renderer. It can recover from lost or corrupt data by searching for the next `GF` magic value.

## Commands

| Opcode | Name | Payload |
| ---: | --- | --- |
| `00` | Set rotation | One 8-bit angle |
| `01` | Begin frame | Empty |
| `02` | Draw triangle | Nine signed Q8.8 coordinates followed by one palette index |
| `03` | End frame | Empty |
| `04` | Set palette | Palette index, red, green, blue |

`Begin frame` clears the back color buffer and Z-buffer. Draw commands then enter the existing ready/valid graphics pipeline. `End frame` waits for all triangles to finish and swaps buffers during vertical blanking.

The draw payload order is `x0, y0, z0, x1, y1, z1, x2, y2, z2, color`. Each coordinate uses two bytes. Values range from -128.0 through 127.99609375 in steps of 1/256.
