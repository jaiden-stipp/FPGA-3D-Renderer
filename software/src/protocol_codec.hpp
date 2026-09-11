#pragma once

#include "fpga_renderer/renderer.hpp"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace fpga_renderer::detail {

struct WireStatus {
    StatusEvent event = StatusEvent::PacketAcknowledged;
    std::uint32_t id = 0;
    std::uint16_t sequence = 0;
    std::uint16_t fifoFree = 0;
    std::uint32_t flags = 0;
    bool hasStatistics = false;
    FrameStatistics statistics;
};

std::vector<std::uint8_t> makeTransportPacket(
    const std::vector<std::uint8_t>& commands,
    std::size_t offset,
    std::size_t size,
    std::uint32_t submissionId,
    std::uint16_t sequence,
    bool first,
    bool last);

bool decodeStatusPacket(const std::uint8_t* data,
                        std::size_t size,
                        WireStatus& status);

}
