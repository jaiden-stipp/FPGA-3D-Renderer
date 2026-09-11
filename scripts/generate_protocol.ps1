param([switch]$Check)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$specificationPath = Join-Path $repository 'protocol/protocol.json'
$specification = Get-Content -LiteralPath $specificationPath -Raw | ConvertFrom-Json

$systemVerilog = @"
``ifndef PROTOCOL_GENERATED_SVH
``define PROTOCOL_GENERATED_SVH

``define GFX_TRANSPORT_VERSION 8'h$('{0:X2}' -f $specification.transportVersion)
``define GFX_COMMAND_VERSION 8'h$('{0:X2}' -f $specification.commandVersion)
``define GFX_STATUS_VERSION 8'h$('{0:X2}' -f $specification.statusVersion)
``define GFX_MAX_DATAGRAM_BYTES $($specification.maximumDatagramBytes)
``define GFX_TRANSPORT_HEADER_BYTES $($specification.transportHeaderBytes)
``define GFX_PACKET_ACK_BYTES $($specification.packetAcknowledgementBytes)
``define GFX_FRAME_STATUS_BYTES $($specification.frameStatusBytes)
``define GFX_RECEIVE_FIFO_BYTES $($specification.receiveFifoBytes)
``define GFX_MESH_HANDLE_COUNT $($specification.meshHandleCount)
``define GFX_VERTICES_PER_MESH $($specification.verticesPerMesh)
``define GFX_TRIANGLES_PER_MESH $($specification.trianglesPerMesh)
``define GFX_SYSTEM_CLOCK_HZ $($specification.systemClockHz)
``define GFX_RENDER_WIDTH $($specification.renderWidth)
``define GFX_RENDER_HEIGHT $($specification.renderHeight)
``define GFX_DISPLAY_WIDTH $($specification.displayWidth)
``define GFX_DISPLAY_HEIGHT $($specification.displayHeight)
``define GFX_DEFAULT_UDP_PORT $($specification.defaultUdpPort)
``define GFX_COMMAND_MAGIC_0 8'h$('{0:X2}' -f $specification.magic.command[0])
``define GFX_COMMAND_MAGIC_1 8'h$('{0:X2}' -f $specification.magic.command[1])
``define GFX_TRANSPORT_MAGIC_0 8'h$('{0:X2}' -f $specification.magic.transport[0])
``define GFX_TRANSPORT_MAGIC_1 8'h$('{0:X2}' -f $specification.magic.transport[1])
``define GFX_STATUS_MAGIC_0 8'h$('{0:X2}' -f $specification.magic.status[0])
``define GFX_STATUS_MAGIC_1 8'h$('{0:X2}' -f $specification.magic.status[1])
``define GFX_STATUS_EVENT_PACKET_ACKNOWLEDGED 8'd$($specification.statusEvents.packetAcknowledged)
``define GFX_STATUS_EVENT_FRAME_DISPLAYED 8'd$($specification.statusEvents.frameDisplayed)
``define GFX_STATUS_ACCEPTED 32'h$('{0:X8}' -f $specification.statusFlags.accepted)
``define GFX_STATUS_DUPLICATE 32'h$('{0:X8}' -f $specification.statusFlags.duplicate)
``define GFX_STATUS_BUSY 32'h$('{0:X8}' -f $specification.statusFlags.busy)
``define GFX_STATUS_SEQUENCE_ERROR 32'h$('{0:X8}' -f $specification.statusFlags.sequenceError)
``define GFX_STATUS_MALFORMED 32'h$('{0:X8}' -f $specification.statusFlags.malformed)
``define GFX_STATUS_OVERFLOW 32'h$('{0:X8}' -f $specification.statusFlags.overflow)
``define GFX_STATUS_DECODER_ERROR 32'h$('{0:X8}' -f $specification.statusFlags.decoderError)
``define GFX_STATUS_COMMAND_ERROR 32'h$('{0:X8}' -f $specification.statusFlags.commandError)
``define GFX_STATUS_RECEIVE_OVERFLOW 32'h$('{0:X8}' -f $specification.statusFlags.receiveOverflow)
``define GFX_BEGIN_FRAME_PAYLOAD_BYTES $($specification.commandPayloadBytes.beginFrame)
``define GFX_DRAW_TRIANGLE_PAYLOAD_BYTES $($specification.commandPayloadBytes.drawTriangle)
``define GFX_END_FRAME_PAYLOAD_BYTES $($specification.commandPayloadBytes.endFrame)
``define GFX_SET_PALETTE_PAYLOAD_BYTES $($specification.commandPayloadBytes.setPalette)
``define GFX_DEFINE_MESH_PAYLOAD_BYTES $($specification.commandPayloadBytes.defineMesh)
``define GFX_UPLOAD_VERTEX_PAYLOAD_BYTES $($specification.commandPayloadBytes.uploadVertex)
``define GFX_UPLOAD_INDEX_PAYLOAD_BYTES $($specification.commandPayloadBytes.uploadIndex)
``define GFX_DRAW_MESH_PAYLOAD_BYTES $($specification.commandPayloadBytes.drawMesh)
``define GFX_SET_VIEW_MATRIX_PAYLOAD_BYTES $($specification.commandPayloadBytes.setViewMatrix)
``define GFX_SET_PROJECTION_PAYLOAD_BYTES $($specification.commandPayloadBytes.setProjection)

``define GFX_WIRE_CMD_BEGIN_FRAME 8'd$($specification.opcodes.beginFrame)
``define GFX_WIRE_CMD_DRAW_TRIANGLE 8'd$($specification.opcodes.drawTriangle)
``define GFX_WIRE_CMD_END_FRAME 8'd$($specification.opcodes.endFrame)
``define GFX_WIRE_CMD_SET_PALETTE 8'd$($specification.opcodes.setPalette)
``define GFX_WIRE_CMD_DEFINE_MESH 8'd$($specification.opcodes.defineMesh)
``define GFX_WIRE_CMD_UPLOAD_VERTEX 8'd$($specification.opcodes.uploadVertex)
``define GFX_WIRE_CMD_UPLOAD_INDEX 8'd$($specification.opcodes.uploadIndex)
``define GFX_WIRE_CMD_DRAW_MESH 8'd$($specification.opcodes.drawMesh)
``define GFX_WIRE_CMD_UPLOAD_VERTICES 8'd$($specification.opcodes.uploadVertices)
``define GFX_WIRE_CMD_UPLOAD_INDICES 8'd$($specification.opcodes.uploadIndices)
``define GFX_WIRE_CMD_SET_VIEW_MATRIX 8'd$($specification.opcodes.setViewMatrix)
``define GFX_WIRE_CMD_SET_PROJECTION 8'd$($specification.opcodes.setProjection)

``endif
"@

$cpp = @"
#pragma once

#include <cstddef>
#include <cstdint>

namespace fpga_renderer::protocol {

inline constexpr std::uint8_t transportVersion = $($specification.transportVersion);
inline constexpr std::uint8_t commandVersion = $($specification.commandVersion);
inline constexpr std::uint8_t statusVersion = $($specification.statusVersion);
inline constexpr std::size_t maximumDatagramBytes = $($specification.maximumDatagramBytes);
inline constexpr std::size_t transportHeaderBytes = $($specification.transportHeaderBytes);
inline constexpr std::size_t packetAcknowledgementBytes = $($specification.packetAcknowledgementBytes);
inline constexpr std::size_t frameStatusBytes = $($specification.frameStatusBytes);
inline constexpr std::size_t receiveFifoBytes = $($specification.receiveFifoBytes);
inline constexpr std::size_t meshHandleCount = $($specification.meshHandleCount);
inline constexpr std::size_t verticesPerMesh = $($specification.verticesPerMesh);
inline constexpr std::size_t trianglesPerMesh = $($specification.trianglesPerMesh);
inline constexpr std::uint32_t systemClockHz = $($specification.systemClockHz);
inline constexpr std::size_t renderWidth = $($specification.renderWidth);
inline constexpr std::size_t renderHeight = $($specification.renderHeight);
inline constexpr std::size_t displayWidth = $($specification.displayWidth);
inline constexpr std::size_t displayHeight = $($specification.displayHeight);
inline constexpr std::uint16_t defaultUdpPort = $($specification.defaultUdpPort);
inline constexpr std::uint8_t commandMagic0 = $($specification.magic.command[0]);
inline constexpr std::uint8_t commandMagic1 = $($specification.magic.command[1]);
inline constexpr std::uint8_t transportMagic0 = $($specification.magic.transport[0]);
inline constexpr std::uint8_t transportMagic1 = $($specification.magic.transport[1]);
inline constexpr std::uint8_t statusMagic0 = $($specification.magic.status[0]);
inline constexpr std::uint8_t statusMagic1 = $($specification.magic.status[1]);

enum class StatusEvent : std::uint8_t {
    PacketAcknowledged = $($specification.statusEvents.packetAcknowledged),
    FrameDisplayed = $($specification.statusEvents.frameDisplayed)
};

inline constexpr std::uint32_t statusAccepted = $($specification.statusFlags.accepted);
inline constexpr std::uint32_t statusDuplicate = $($specification.statusFlags.duplicate);
inline constexpr std::uint32_t statusBusy = $($specification.statusFlags.busy);
inline constexpr std::uint32_t statusSequenceError = $($specification.statusFlags.sequenceError);
inline constexpr std::uint32_t statusMalformed = $($specification.statusFlags.malformed);
inline constexpr std::uint32_t statusOverflow = $($specification.statusFlags.overflow);
inline constexpr std::uint32_t statusDecoderError = $($specification.statusFlags.decoderError);
inline constexpr std::uint32_t statusCommandError = $($specification.statusFlags.commandError);
inline constexpr std::uint32_t statusReceiveOverflow = $($specification.statusFlags.receiveOverflow);

namespace payloadBytes {
inline constexpr std::size_t beginFrame = $($specification.commandPayloadBytes.beginFrame);
inline constexpr std::size_t drawTriangle = $($specification.commandPayloadBytes.drawTriangle);
inline constexpr std::size_t endFrame = $($specification.commandPayloadBytes.endFrame);
inline constexpr std::size_t setPalette = $($specification.commandPayloadBytes.setPalette);
inline constexpr std::size_t defineMesh = $($specification.commandPayloadBytes.defineMesh);
inline constexpr std::size_t uploadVertex = $($specification.commandPayloadBytes.uploadVertex);
inline constexpr std::size_t uploadIndex = $($specification.commandPayloadBytes.uploadIndex);
inline constexpr std::size_t drawMesh = $($specification.commandPayloadBytes.drawMesh);
inline constexpr std::size_t setViewMatrix = $($specification.commandPayloadBytes.setViewMatrix);
inline constexpr std::size_t setProjection = $($specification.commandPayloadBytes.setProjection);
}

enum class Opcode : std::uint8_t {
    BeginFrame = $($specification.opcodes.beginFrame),
    DrawTriangle = $($specification.opcodes.drawTriangle),
    EndFrame = $($specification.opcodes.endFrame),
    SetPalette = $($specification.opcodes.setPalette),
    DefineMesh = $($specification.opcodes.defineMesh),
    UploadVertex = $($specification.opcodes.uploadVertex),
    UploadIndex = $($specification.opcodes.uploadIndex),
    DrawMesh = $($specification.opcodes.drawMesh),
    UploadVertices = $($specification.opcodes.uploadVertices),
    UploadIndices = $($specification.opcodes.uploadIndices),
    SetViewMatrix = $($specification.opcodes.setViewMatrix),
    SetProjection = $($specification.opcodes.setProjection)
};

}
"@

$outputs = @{
    (Join-Path $repository 'rtl/common/protocol_generated.svh') = $systemVerilog
    (Join-Path $repository 'software/include/fpga_renderer/protocol_generated.hpp') = $cpp
}

foreach ($entry in $outputs.GetEnumerator()) {
    $expected = $entry.Value.Replace("`r`n", "`n").TrimEnd() + "`n"
    if ($Check) {
        $actual = if (Test-Path -LiteralPath $entry.Key) {
            (Get-Content -LiteralPath $entry.Key -Raw).Replace("`r`n", "`n")
        } else {
            ''
        }
        if ($actual -ne $expected) {
            throw "Generated protocol file is stale: $($entry.Key)"
        }
    } else {
        [System.IO.File]::WriteAllText($entry.Key, $expected,
            [System.Text.UTF8Encoding]::new($false))
    }
}

if ($Check) {
    Write-Host 'Protocol definitions are current.'
} else {
    Write-Host 'Protocol definitions regenerated.'
}
