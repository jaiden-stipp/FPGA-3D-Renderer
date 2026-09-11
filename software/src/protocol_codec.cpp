#include "protocol_codec.hpp"

#include <stdexcept>
#include <string>

namespace fpga_renderer::detail {

namespace {

void append16(std::vector<std::uint8_t>& output, std::uint16_t value) {
    output.push_back(static_cast<std::uint8_t>(value >> 8));
    output.push_back(static_cast<std::uint8_t>(value));
}

void append32(std::vector<std::uint8_t>& output, std::uint32_t value) {
    output.push_back(static_cast<std::uint8_t>(value >> 24));
    output.push_back(static_cast<std::uint8_t>(value >> 16));
    output.push_back(static_cast<std::uint8_t>(value >> 8));
    output.push_back(static_cast<std::uint8_t>(value));
}

std::uint16_t read16(const std::uint8_t* data) {
    return static_cast<std::uint16_t>((static_cast<std::uint16_t>(data[0]) << 8) |
                                      data[1]);
}

std::uint32_t read32(const std::uint8_t* data) {
    return (static_cast<std::uint32_t>(data[0]) << 24) |
           (static_cast<std::uint32_t>(data[1]) << 16) |
           (static_cast<std::uint32_t>(data[2]) << 8) |
           data[3];
}

void decodeVersion1Statistics(const std::uint8_t* data, FrameStatistics& stats) {
    stats.trianglesSubmitted = read32(data + 16);
    stats.trianglesClipped = read32(data + 20);
    stats.trianglesCulled = read32(data + 24);
    stats.boundingBoxPixels = read32(data + 28);
    stats.pixelsInside = read32(data + 32);
    stats.depthRejected = read32(data + 36);
    stats.pixelsWritten = read32(data + 40);
    stats.geometryCycles = read32(data + 44);
    stats.rasterCycles = read32(data + 48);
    stats.totalCycles = read32(data + 52);
    stats.swapWaitCycles = read32(data + 56);
}

void decodeVersion2Statistics(const std::uint8_t* data, FrameStatistics& stats) {
    stats.trianglesSubmitted = read32(data + 16);
    stats.trianglesClipped = read32(data + 20);
    stats.trianglesCulled = read32(data + 24);
    stats.boundingBoxPixels = read32(data + 28);
    stats.pixelsInside = read32(data + 32);
    stats.depthRejected = read32(data + 36);
    stats.pixelsWritten = read32(data + 40);
    stats.geometryCycles = read32(data + 44);
    stats.geometryStallCycles = read32(data + 48);
    stats.rasterCycles = read32(data + 52);
    stats.clearCycles = read32(data + 56);
    stats.totalCycles = read32(data + 60);
    stats.swapWaitCycles = read32(data + 64);
}

}

std::vector<std::uint8_t> makeTransportPacket(
    const std::vector<std::uint8_t>& commands,
    std::size_t offset,
    std::size_t size,
    std::uint32_t submissionId,
    std::uint16_t sequence,
    bool first,
    bool last) {
    std::vector<std::uint8_t> packet;
    packet.reserve(protocol::transportHeaderBytes + size);
    packet.push_back(protocol::transportMagic0);
    packet.push_back(protocol::transportMagic1);
    packet.push_back(protocol::transportVersion);
    packet.push_back(static_cast<std::uint8_t>((first ? 1U : 0U) |
                                               (last ? 2U : 0U)));
    append32(packet, submissionId);
    append16(packet, sequence);
    append16(packet, static_cast<std::uint16_t>(size));
    packet.insert(packet.end(), commands.begin() + static_cast<std::ptrdiff_t>(offset),
                  commands.begin() + static_cast<std::ptrdiff_t>(offset + size));
    return packet;
}

bool decodeStatusPacket(const std::uint8_t* data,
                        std::size_t size,
                        WireStatus& status) {
    if (size < 2 || data[0] != protocol::statusMagic0 ||
        data[1] != protocol::statusMagic1)
        return false;
    if (size < 4)
        throw std::runtime_error("received a truncated FPGA status packet");
    const std::uint8_t version = data[2];
    if (version != 1 && version != protocol::statusVersion)
        throw std::runtime_error("FPGA status protocol version " +
                                 std::to_string(version) + " is not supported");
    if (data[3] != static_cast<std::uint8_t>(StatusEvent::PacketAcknowledged) &&
        data[3] != static_cast<std::uint8_t>(StatusEvent::FrameDisplayed))
        throw std::runtime_error("received an unknown FPGA status event");

    const bool acknowledgement = data[3] == 1;
    const bool validVersion1 = version == 1 &&
        ((acknowledgement && size == 20) ||
         (!acknowledgement && (size == 20 || size == 60)));
    const bool validVersion2 = version == protocol::statusVersion &&
        ((acknowledgement && size == protocol::packetAcknowledgementBytes) ||
         (!acknowledgement && size == protocol::frameStatusBytes));
    if (!validVersion1 && !validVersion2)
        throw std::runtime_error("FPGA status packet size " + std::to_string(size) +
                                 " does not match protocol version " +
                                 std::to_string(version));

    status = {};
    status.event = static_cast<StatusEvent>(data[3]);
    status.id = read32(data + 4);
    status.sequence = read16(data + 8);
    status.fifoFree = read16(data + 10);
    status.flags = read32(data + 12);
    status.hasStatistics = (!acknowledgement && size > 20);
    if (version == 1 && size == 60)
        decodeVersion1Statistics(data, status.statistics);
    else if (version == protocol::statusVersion && !acknowledgement)
        decodeVersion2Statistics(data, status.statistics);
    return true;
}

}
