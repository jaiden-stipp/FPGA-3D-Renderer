# Ethernet Interface

The DE2-115 receives graphics command streams as UDP payloads through ENET0.

## Network Settings

- FPGA address: `192.168.7.2`
- FPGA MAC address: `02:00:00:00:00:01`
- UDP port: `4000`
- Link mode: 100 Mb/s MII
- Maximum payload used by the C++ test transport: 1400 bytes

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

The receive parser accepts untagged Ethernet II frames with a normal 20-byte IPv4 header. It filters packets by the FPGA IP address and UDP port. Each accepted UDP payload is passed unchanged to the graphics command decoder. Command framing and CRC recovery can continue across UDP packet boundaries.

This first transport has no acknowledgements or renderer flow control. A single demo scene fits in one packet and is safe. Do not send a new frame until the previous frame has had time to render. Packets are dropped if the receive FIFO fills.

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

The program sends a 12-triangle colored cube. When the renderer finishes the frame, the completed back buffer becomes visible on the 640 x 480 VGA display.

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
- No transmit path except ARP replies
- No packet acknowledgement or automatic retry
