#include "fpga_renderer/renderer.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <thread>
#include <vector>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

using namespace fpga_renderer;

namespace {

void require(bool condition, const char* message = "renderer test requirement failed") {
    if (!condition)
        throw std::runtime_error(message);
}

void write16(std::vector<std::uint8_t>& bytes, std::size_t offset,
             std::uint16_t value) {
    bytes[offset] = static_cast<std::uint8_t>(value >> 8);
    bytes[offset + 1] = static_cast<std::uint8_t>(value);
}

void write32(std::vector<std::uint8_t>& bytes, std::size_t offset,
             std::uint32_t value) {
    bytes[offset] = static_cast<std::uint8_t>(value >> 24);
    bytes[offset + 1] = static_cast<std::uint8_t>(value >> 16);
    bytes[offset + 2] = static_cast<std::uint8_t>(value >> 8);
    bytes[offset + 3] = static_cast<std::uint8_t>(value);
}

std::uint16_t read16(const std::uint8_t* bytes) {
    return static_cast<std::uint16_t>((static_cast<std::uint16_t>(bytes[0]) << 8) |
                                      bytes[1]);
}

std::uint32_t read32(const std::uint8_t* bytes) {
    return (static_cast<std::uint32_t>(bytes[0]) << 24) |
           (static_cast<std::uint32_t>(bytes[1]) << 16) |
           (static_cast<std::uint32_t>(bytes[2]) << 8) | bytes[3];
}

void testChunkedTransport() {
#ifdef _WIN32
    WSADATA winsock{};
    require(WSAStartup(MAKEWORD(2, 2), &winsock) == 0,
            "could not initialize test Winsock");
    const SOCKET server = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    require(server != INVALID_SOCKET, "could not create test UDP socket");
#else
    const int server = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    require(server >= 0, "could not create test UDP socket");
#endif
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    require(bind(server, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == 0,
            "could not bind test UDP socket");
#ifdef _WIN32
    int addressLength = sizeof(address);
#else
    socklen_t addressLength = sizeof(address);
#endif
    require(getsockname(server, reinterpret_cast<sockaddr*>(&address), &addressLength) == 0,
            "could not read test UDP port");
    const std::uint16_t port = ntohs(address.sin_port);

    CommandStream large;
    large.beginFrame(0x89ABCDEF);
    for (int index = 0; index < 60; ++index) {
        large.drawTriangle({{0.0F, 0.0F, 0.0F}, {1.0F, 0.0F, 0.0F},
                            {0.0F, 1.0F, 0.0F}, 1});
    }
    large.endFrame();
    require(large.bytes().size() > 1400);

    std::vector<std::uint8_t> receivedCommands;
    int packetCount = 0;
    std::uint32_t submissionId = 0;
    bool serverValid = true;
    std::thread fakeFpga([&] {
        std::array<std::uint8_t, 1600> packet{};
        bool last = false;
        while (!last) {
            sockaddr_in peer{};
#ifdef _WIN32
            int peerLength = sizeof(peer);
            const int received = recvfrom(server, reinterpret_cast<char*>(packet.data()),
                                          static_cast<int>(packet.size()), 0,
                                          reinterpret_cast<sockaddr*>(&peer), &peerLength);
#else
            socklen_t peerLength = sizeof(peer);
            const auto received = recvfrom(server, packet.data(), packet.size(), 0,
                                           reinterpret_cast<sockaddr*>(&peer), &peerLength);
#endif
            if (received < 12 || packet[0] != 0x47 || packet[1] != 0x50 ||
                packet[2] != 1) {
                serverValid = false;
                return;
            }
            const std::uint32_t receivedSubmissionId = read32(packet.data() + 4);
            if (packetCount == 0)
                submissionId = receivedSubmissionId;
            else if (receivedSubmissionId != submissionId) {
                serverValid = false;
                return;
            }
            const std::uint16_t sequence = read16(packet.data() + 8);
            const std::uint16_t length = read16(packet.data() + 10);
            if (sequence != packetCount || received != 12 + length) {
                serverValid = false;
                return;
            }
            receivedCommands.insert(receivedCommands.end(), packet.begin() + 12,
                                    packet.begin() + 12 + length);
            last = (packet[3] & 2U) != 0;

            std::vector<std::uint8_t> status(20, 0);
            status[0] = 0x47;
            status[1] = 0x53;
            status[2] = 1;
            status[3] = 1;
            write32(status, 4, submissionId);
            write16(status, 8, sequence);
            write16(status, 10, 2048);
            write32(status, 12, StatusAccepted);
#ifdef _WIN32
            sendto(server, reinterpret_cast<const char*>(status.data()),
                   static_cast<int>(status.size()), 0,
                   reinterpret_cast<const sockaddr*>(&peer), peerLength);
#else
            sendto(server, status.data(), status.size(), 0,
                   reinterpret_cast<const sockaddr*>(&peer), peerLength);
#endif
            ++packetCount;
            if (last) {
                status[3] = 2;
                write32(status, 4, 0x89ABCDEF);
#ifdef _WIN32
                sendto(server, reinterpret_cast<const char*>(status.data()),
                       static_cast<int>(status.size()), 0,
                       reinterpret_cast<const sockaddr*>(&peer), peerLength);
#else
                sendto(server, status.data(), status.size(), 0,
                       reinterpret_cast<const sockaddr*>(&peer), peerLength);
#endif
            }
        }
    });

    RendererStatus status{};
    {
        RendererClient client("127.0.0.1", port);
        status = client.submit(large);
    }
    fakeFpga.join();
    require(serverValid);
    require(packetCount >= 2);
    require(receivedCommands == large.bytes());
    require(status.event == StatusEvent::FrameDisplayed);
    require(status.frameId == 0x89ABCDEF);

#ifdef _WIN32
    closesocket(server);
    WSACleanup();
#else
    close(server);
#endif
}

}

int main() {
    CommandStream stream;
    stream.setRotation(0x5A);
    require(stream.bytes() == std::vector<std::uint8_t>({
        0x47, 0x46, 0x01, 0x00, 0x01, 0x5A, 0xCE, 0x96
    }));

    stream.clear();
    stream.setPalette(0x07, {0xA1, 0xB2, 0xC3});
    require(stream.bytes() == std::vector<std::uint8_t>({
        0x47, 0x46, 0x01, 0x04, 0x04, 0x07, 0xA1, 0xB2, 0xC3, 0xFD, 0x1C
    }));

    Mesh indexedMesh;
    indexedMesh.addTriangle({{-1, -1, 0}, {-1, 1, 0}, {1, 1, 0}, 3});
    indexedMesh.addTriangle({{-1, -1, 0}, {1, 1, 0}, {1, -1, 0}, 3});
    CommandStream upload;
    upload.uploadMesh(2, indexedMesh);
    require(upload.bytes().size() == 65);
    require(upload.bytes()[3] == static_cast<std::uint8_t>(Opcode::DefineMesh));
    require(upload.bytes()[4] == 5);
    require(upload.bytes()[5] == 2);
    require(upload.bytes()[7] == 4);
    require(upload.bytes()[9] == 2);
    require(upload.bytes()[15] == static_cast<std::uint8_t>(Opcode::UploadVertices));
    require(upload.bytes()[16] == 27 && upload.bytes()[19] == 4);
    require(upload.bytes()[49] == static_cast<std::uint8_t>(Opcode::UploadIndices));
    require(upload.bytes()[50] == 12 && upload.bytes()[54] == 2);

    Mesh quantizedMesh;
    quantizedMesh.addTriangle({{0.0F, 0.0F, 0.0F}, {0.001F, 0.0F, 0.0F},
                               {1.0F, 0.0F, 0.0F}, 4});
    CommandStream quantizedUpload;
    quantizedUpload.uploadMesh(3, quantizedMesh);
    require(quantizedUpload.bytes()[7] == 2,
            "vertices equal in Q8.8 must share an uploaded index");

    CommandStream indexedDraw;
    indexedDraw.beginFrame(0x10203040);
    indexedDraw.drawMesh(2, Mat4::translation(2.0F, 0.0F, 0.0F));
    indexedDraw.drawMesh(2, Mat4::translation(-2.0F, 0.0F, 0.0F));
    indexedDraw.endFrame();
    require(indexedDraw.bytes().size() == 82);
    require(indexedDraw.bytes()[14] == static_cast<std::uint8_t>(Opcode::DrawMesh));
    require(indexedDraw.bytes()[15] == 25);
    require(indexedDraw.bytes()[16] == 2);
    require(indexedDraw.bytes()[23] == 0x02 && indexedDraw.bytes()[24] == 0x00);
    require(indexedDraw.bytes()[46] == static_cast<std::uint8_t>(Opcode::DrawMesh));
    require(indexedDraw.bytes()[55] == 0xFE && indexedDraw.bytes()[56] == 0x00);

    stream.clear();
    stream.beginFrame(0x12345678);
    stream.drawTriangle({
        {1.0F, -1.0F, 0.5F},
        {2.0F, 0.0F, -0.5F},
        {-2.0F, 1.0F, 0.0F},
        0x2F
    });
    require(stream.bytes() == std::vector<std::uint8_t>({
        0x47, 0x46, 0x01, 0x01, 0x04, 0x12, 0x34, 0x56, 0x78, 0x40, 0xF0,
        0x47, 0x46, 0x01, 0x02, 0x13,
        0x01, 0x00, 0xFF, 0x00, 0x00, 0x80,
        0x02, 0x00, 0x00, 0x00, 0xFF, 0x80,
        0xFE, 0x00, 0x01, 0x00, 0x00, 0x00, 0x2F,
        0x58, 0xD8
    }));
    stream.endFrame();
    require(stream.frameId() == 0x12345678);

    const Mat4 transform = Mat4::translation(1.0F, 2.0F, 3.0F) *
                           Mat4::scale(2.0F, 2.0F, 2.0F);
    const Vec3 point = transform.transformPoint({1.0F, 0.0F, 0.0F});
    require(std::abs(point.x - 3.0F) < 0.0001F);
    require(std::abs(point.y - 2.0F) < 0.0001F);
    require(std::abs(point.z - 3.0F) < 0.0001F);

    bool rejected = false;
    try {
        static_cast<void>(toQ8_8(128.0F));
    } catch (const std::out_of_range&) {
        rejected = true;
    }
    require(rejected);

    bool missingFrameRejected = false;
    try {
        CommandStream empty;
        static_cast<void>(empty.frameId());
    } catch (const std::logic_error&) {
        missingFrameRejected = true;
    }
    require(missingFrameRejected);

    testChunkedTransport();
}
