#include "fpga_renderer/renderer.hpp"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

using namespace fpga_renderer;

int main() {
    CommandStream stream;
    stream.setRotation(0x5A);
    assert(stream.bytes() == std::vector<std::uint8_t>({
        0x47, 0x46, 0x01, 0x00, 0x01, 0x5A, 0xCE, 0x96
    }));

    stream.clear();
    stream.setPalette(0x07, {0xA1, 0xB2, 0xC3});
    assert(stream.bytes() == std::vector<std::uint8_t>({
        0x47, 0x46, 0x01, 0x04, 0x04, 0x07, 0xA1, 0xB2, 0xC3, 0xFD, 0x1C
    }));

    stream.clear();
    stream.beginFrame();
    stream.drawTriangle({
        {1.0F, -1.0F, 0.5F},
        {2.0F, 0.0F, -0.5F},
        {-2.0F, 1.0F, 0.0F},
        0x2F
    });
    assert(stream.bytes() == std::vector<std::uint8_t>({
        0x47, 0x46, 0x01, 0x01, 0x00, 0x2A, 0xB4,
        0x47, 0x46, 0x01, 0x02, 0x13,
        0x01, 0x00, 0xFF, 0x00, 0x00, 0x80,
        0x02, 0x00, 0x00, 0x00, 0xFF, 0x80,
        0xFE, 0x00, 0x01, 0x00, 0x00, 0x00, 0x2F,
        0x58, 0xD8
    }));

    stream.endFrame();

    const Mat4 transform = Mat4::translation(1.0F, 2.0F, 3.0F) *
                           Mat4::scale(2.0F, 2.0F, 2.0F);
    const Vec3 point = transform.transformPoint({1.0F, 0.0F, 0.0F});
    assert(std::abs(point.x - 3.0F) < 0.0001F);
    assert(std::abs(point.y - 2.0F) < 0.0001F);
    assert(std::abs(point.z - 3.0F) < 0.0001F);

    bool rejected = false;
    try {
        static_cast<void>(toQ8_8(128.0F));
    } catch (const std::out_of_range&) {
        rejected = true;
    }
    assert(rejected);

    bool emptyRejected = false;
    try {
        sendUdp("192.168.7.2", 4000, std::vector<std::uint8_t>{});
    } catch (const std::invalid_argument&) {
        emptyRejected = true;
    }
    assert(emptyRejected);

    bool oversizedRejected = false;
    try {
        sendUdp("192.168.7.2", 4000, std::vector<std::uint8_t>(1401));
    } catch (const std::length_error&) {
        oversizedRejected = true;
    }
    assert(oversizedRejected);
}
