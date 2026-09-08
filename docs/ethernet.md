# Ethernet Interface

The DE2-115 receives graphics command streams as UDP payloads through ENET0.

## Network Settings

- FPGA address: `192.168.7.2`
- FPGA MAC address: `02:00:00:00:00:01`
- UDP port: `4000`
- Link mode: 100 Mb/s MII
- Maximum UDP payload: 1400 bytes, including the 12-byte transport header

The FPGA answers ARP requests for its fixed address. It does not use DHCP and does not answer ping.

## Data Path

```text
ENET0 MII receive pins
        |
Ethernet, IPv4, and UDP parser
        |
2048-byte dual-clock FIFO
        |
Graphics command stream decoder
        |
Command processor and renderer
        |
Double-buffered VGA output
```

The receive parser accepts untagged Ethernet II frames with a normal 20-byte IPv4 header. It filters packets by the FPGA IP address and UDP port. A transport header identifies each submission and orders its packets. Accepted command bytes can continue across packet boundaries.

The C++ client sends one packet at a time. It waits for an acknowledgement, retries a lost packet, and pauses when the FPGA reports that its FIFO is full. A mesh upload returns after its final packet is accepted. A frame submission waits until its frame ID is displayed before another frame can be submitted. Upload commands and the next frame stay ordered in the receive FIFO.

## Packet Format

Every host-to-FPGA UDP payload starts with this header. Multi-byte fields are big-endian.

| Field | Bytes | Value |
| --- | ---: | --- |
| Magic | 2 | `47 50` (`GP`) |
| Version | 1 | `01` |
| Flags | 1 | Bit 0: first packet, bit 1: last packet |
| Submission ID | 4 | Orders transport packets and identifies acknowledgements |
| Sequence | 2 | Starts at zero and rises by one |
| Command length | 2 | Bytes after this header |
| Command bytes | 0-1388 | Part of the graphics command stream |

Scenes larger than 1388 command bytes are split into sequenced packets. The current C++ client keeps each complete UDP payload at or below 1400 bytes.
The C++ client assigns a new submission ID to each upload or frame transfer. The separate `BEGIN_FRAME` ID is returned when that frame reaches the display.

## Status Format

The FPGA sends a 20-byte UDP status payload back to the source port used by the client.

| Field | Bytes | Value |
| --- | ---: | --- |
| Magic | 2 | `47 53` (`GS`) |
| Version | 1 | `01` |
| Event | 1 | `01`: packet acknowledgement, `02`: frame displayed |
| ID | 4 | Submission ID for acknowledgements; `BEGIN_FRAME` ID for display events |
| Sequence | 2 | Packet sequence number |
| FIFO free | 2 | Free bytes in the 2048-byte receive FIFO |
| Status flags | 4 | Result and error bits |
| Reserved | 4 | Zero |

Status flag bits are: accepted (0), duplicate retry (1), busy (2), sequence error (3), malformed packet (4), receive overflow (5), command CRC/decoder error (8), renderer command error (9), and clock-crossing FIFO overflow (10).

## DE2-115 Setup

1. Turn off the board.
2. Move ENET0 jumper `JP1` so it shorts pins 2 and 3. This selects MII mode.
3. Set `SW[0]` to ON for Ethernet input.
4. Connect ENET0 and the computer with an Ethernet cable.
5. Connect the VGA display.
6. Power on the board and program `output_files/Graphics.sof`.
7. Press and release `KEY[0]`.

Changing JP1 requires a hardware reset or power cycle. Shorting JP1 pins 1 and 2 selects RGMII and will not work with this design.

## Computer Setup

Set the wired Ethernet adapter to a manual IPv4 address:

- Address: `192.168.7.1`
- Subnet mask: `255.255.255.0`
- Gateway: leave blank
- DNS: leave blank

Wait for the link lights, then run:

```text
build\software\Release\renderer_udp_demo.exe 192.168.7.2 4000
```

If `LEDG[1]` stays off, set the computer adapter's Speed and Duplex setting to `100 Mbps Full Duplex`, reconnect the cable, and reset the board.

The program sends a 12-triangle colored cube, waits for its packet acknowledgements, then prints the displayed frame ID, FIFO space, and error flags after the page swap.

## VGA Scene Tests

`renderer_scene_tests` sends visual diagnostics through the same reliable transport:

```text
build\software\Release\renderer_scene_tests.exe palette 192.168.7.2 4000
build\software\Release\renderer_scene_tests.exe depth 192.168.7.2 4000
build\software\Release\renderer_scene_tests.exe clipping 192.168.7.2 4000
build\software\Release\renderer_scene_tests.exe stress 192.168.7.2 4000
build\software\Release\renderer_scene_tests.exe orbit 192.168.7.2 4000 180
```

- `palette` draws a 4 x 4 grid using 16 palette entries.
- `depth` draws three nested triangles in reverse depth order. Yellow should remain in front of red, with blue at the back.
- `clipping` sends triangles that cross the near plane and each side of the screen. The visible parts should stop cleanly at the viewport.
- `stress` draws a 320-triangle colored wave. Its command stream spans several UDP packets and checks sequencing and FIFO flow control.
- `orbit` animates three independently transformed cubes. The last argument controls the number of frames.
- `all` shows each static test for two seconds and then runs the orbit animation.

Each line printed by the program includes the frame ID, command byte count, packet count, completion time, free FIFO bytes, and FPGA status flags. A zero flag value means the completed frame had no reported command or receive errors.

The orbit test uploads one indexed cube to mesh handle 0, then draws that same stored mesh three times per frame with different model matrices.

The green LEDs show the test state:

- `LEDG[0]`: Ethernet command mode is selected
- `LEDG[1]`: the PHY reports a 100 Mb/s link
- `LEDG[2]`: at least one UDP packet was accepted
- `LEDG[3]`: receive overflow, command CRC, or renderer command error

Set `SW[0]` to OFF and press `KEY[0]` to return to the built-in rotating demo.

## Current Protocol Limits

- Static IPv4 only
- No ICMP, DHCP, TCP, VLAN, or IPv4 fragmentation
- IPv4 headers with options are rejected
- Ethernet, IPv4, and UDP checksums are not checked in hardware
- Command CRC errors are detected by the graphics stream decoder
- One host and one frame may be in flight at a time
- Status delivery uses UDP, so the C++ client retries packet acknowledgements and times out if frame completion is lost
