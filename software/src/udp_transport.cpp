#include "fpga_renderer/renderer.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <stdexcept>
#include <string>
#include <thread>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <netdb.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace fpga_renderer {

namespace {

constexpr std::size_t transportHeaderSize = 12;
constexpr std::size_t maximumDatagramSize = 1400;
constexpr std::size_t maximumChunkSize = maximumDatagramSize - transportHeaderSize;
constexpr int packetAttempts = 8;
constexpr auto packetTimeout = std::chrono::milliseconds(300);
constexpr auto busyDelay = std::chrono::milliseconds(10);
constexpr auto frameTimeout = std::chrono::seconds(30);

#ifdef _WIN32
using Socket = SOCKET;
constexpr Socket invalidSocket = INVALID_SOCKET;

class SocketSystem {
public:
    SocketSystem() {
        WSADATA data{};
        if (WSAStartup(MAKEWORD(2, 2), &data) != 0)
            throw std::runtime_error("could not initialize Winsock");
    }

    ~SocketSystem() {
        WSACleanup();
    }
};

void closeSocket(Socket socket) {
    if (socket != invalidSocket)
        closesocket(socket);
}
#else
using Socket = int;
constexpr Socket invalidSocket = -1;

class SocketSystem {};

void closeSocket(Socket socket) {
    if (socket != invalidSocket)
        close(socket);
}
#endif

struct AddressDeleter {
    void operator()(addrinfo* address) const {
        if (address)
            freeaddrinfo(address);
    }
};

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

std::vector<std::uint8_t> makePacket(const std::vector<std::uint8_t>& commands,
                                     std::size_t offset, std::size_t size,
                                     std::uint32_t frameId, std::uint16_t sequence,
                                     bool first, bool last) {
    std::vector<std::uint8_t> packet;
    packet.reserve(transportHeaderSize + size);
    packet.push_back(0x47);
    packet.push_back(0x50);
    packet.push_back(0x01);
    packet.push_back(static_cast<std::uint8_t>((first ? 1U : 0U) |
                                               (last ? 2U : 0U)));
    append32(packet, frameId);
    append16(packet, sequence);
    append16(packet, static_cast<std::uint16_t>(size));
    packet.insert(packet.end(), commands.begin() + static_cast<std::ptrdiff_t>(offset),
                  commands.begin() + static_cast<std::ptrdiff_t>(offset + size));
    return packet;
}

std::string packetError(std::uint32_t flags) {
    if (flags & StatusSequenceError)
        return "FPGA rejected an out-of-sequence packet";
    if (flags & StatusMalformed)
        return "FPGA rejected a malformed packet";
    if (flags & StatusOverflow)
        return "FPGA receive FIFO overflowed";
    return "FPGA rejected a packet";
}

}

class RendererClient::Impl {
public:
    Impl(const std::string& host, std::uint16_t port) {
        addrinfo hints{};
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_DGRAM;
        hints.ai_protocol = IPPROTO_UDP;
        addrinfo* rawAddresses = nullptr;
        const std::string service = std::to_string(port);
        if (getaddrinfo(host.c_str(), service.c_str(), &hints, &rawAddresses) != 0)
            throw std::runtime_error("could not resolve UDP destination " + host);
        std::unique_ptr<addrinfo, AddressDeleter> addresses(rawAddresses);

        for (addrinfo* address = addresses.get(); address; address = address->ai_next) {
            socket_ = ::socket(address->ai_family, address->ai_socktype, address->ai_protocol);
            if (socket_ == invalidSocket)
                continue;
            if (::connect(socket_, address->ai_addr,
                          static_cast<int>(address->ai_addrlen)) == 0)
                return;
            closeSocket(socket_);
            socket_ = invalidSocket;
        }
        throw std::runtime_error("could not connect UDP socket to " + host);
    }

    ~Impl() {
        closeSocket(socket_);
    }

    RendererStatus submit(const CommandStream& stream) {
        const auto& commands = stream.bytes();
        if (commands.empty())
            throw std::invalid_argument("cannot submit an empty command stream");
        const std::uint32_t frameId = stream.frameId();
        sendPackets(commands);

        const auto deadline = std::chrono::steady_clock::now() + frameTimeout;
        while (std::chrono::steady_clock::now() < deadline) {
            RendererStatus status{};
            if (!receiveStatus(deadline - std::chrono::steady_clock::now(), status))
                break;
            if (status.event == StatusEvent::FrameDisplayed && status.frameId == frameId)
                return status;
        }
        throw std::runtime_error("timed out waiting for frame " +
                                 std::to_string(frameId) + " to be displayed");
    }

    RendererStatus upload(const CommandStream& stream) {
        if (stream.bytes().empty())
            throw std::invalid_argument("cannot upload an empty command stream");
        return sendPackets(stream.bytes());
    }

private:
    RendererStatus sendPackets(const std::vector<std::uint8_t>& commands) {
        const std::uint32_t submissionId = ++nextSubmissionId_;
        const std::size_t packetCount =
            (commands.size() + maximumChunkSize - 1) / maximumChunkSize;
        if (packetCount > 65536)
            throw std::length_error("command stream needs more than 65536 packets");

        for (std::size_t packetIndex = 0; packetIndex < packetCount; ++packetIndex) {
            const std::size_t offset = packetIndex * maximumChunkSize;
            const std::size_t size = (std::min)(maximumChunkSize, commands.size() - offset);
            const auto sequence = static_cast<std::uint16_t>(packetIndex);
            const auto packet = makePacket(commands, offset, size, submissionId, sequence,
                                           packetIndex == 0, packetIndex + 1 == packetCount);
            lastPacketStatus_ = acknowledgePacket(packet, submissionId, sequence);
        }
        return lastPacketStatus_;
    }

    RendererStatus acknowledgePacket(const std::vector<std::uint8_t>& packet,
                                     std::uint32_t submissionId,
                                     std::uint16_t sequence) {
        for (int attempt = 0; attempt < packetAttempts; ++attempt) {
#ifdef _WIN32
            const int sent = ::send(socket_, reinterpret_cast<const char*>(packet.data()),
                                    static_cast<int>(packet.size()), 0);
#else
            const auto sent = ::send(socket_, packet.data(), packet.size(), 0);
#endif
            if (sent < 0 || static_cast<std::size_t>(sent) != packet.size())
                throw std::runtime_error("could not send a complete UDP packet");

            const auto deadline = std::chrono::steady_clock::now() + packetTimeout;
            while (std::chrono::steady_clock::now() < deadline) {
                RendererStatus status{};
                if (!receiveStatus(deadline - std::chrono::steady_clock::now(), status))
                    break;
                if (status.event != StatusEvent::PacketAcknowledged ||
                    status.frameId != submissionId || status.sequence != sequence)
                    continue;
                if (status.flags & StatusBusy) {
                    std::this_thread::sleep_for(busyDelay);
                    break;
                }
                if ((status.flags & StatusAccepted) == 0)
                    throw std::runtime_error(packetError(status.flags));
                return status;
            }
        }
        throw std::runtime_error("timed out sending submission " +
                                 std::to_string(submissionId) +
                                 " packet " + std::to_string(sequence));
    }

    template <typename Rep, typename Period>
    bool receiveStatus(std::chrono::duration<Rep, Period> timeout,
                       RendererStatus& status) {
        const auto microseconds = std::chrono::duration_cast<std::chrono::microseconds>(timeout);
        if (microseconds.count() <= 0)
            return false;
        timeval wait{};
        wait.tv_sec = static_cast<long>(microseconds.count() / 1000000);
        wait.tv_usec = static_cast<long>(microseconds.count() % 1000000);
        fd_set sockets;
        FD_ZERO(&sockets);
        FD_SET(socket_, &sockets);
#ifdef _WIN32
        const int ready = select(0, &sockets, nullptr, nullptr, &wait);
#else
        const int ready = select(socket_ + 1, &sockets, nullptr, nullptr, &wait);
#endif
        if (ready == 0)
            return false;
        if (ready < 0)
            throw std::runtime_error("UDP receive wait failed");

        std::array<std::uint8_t, 256> response{};
#ifdef _WIN32
        const int received = recv(socket_, reinterpret_cast<char*>(response.data()),
                                  static_cast<int>(response.size()), 0);
#else
        const auto received = recv(socket_, response.data(), response.size(), 0);
#endif
        if (received < 0)
            throw std::runtime_error("could not receive FPGA status packet");
        if (received != 20 || response[0] != 0x47 || response[1] != 0x53 ||
            response[2] != 0x01 || (response[3] != 1 && response[3] != 2))
            return true;
        status.event = static_cast<StatusEvent>(response[3]);
        status.frameId = read32(response.data() + 4);
        status.sequence = read16(response.data() + 8);
        status.fifoFree = read16(response.data() + 10);
        status.flags = read32(response.data() + 12);
        return true;
    }

    SocketSystem socketSystem_;
    Socket socket_ = invalidSocket;
    std::uint32_t nextSubmissionId_ = static_cast<std::uint32_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
    RendererStatus lastPacketStatus_{};
};

RendererClient::RendererClient(std::string host, std::uint16_t port)
    : impl_(std::make_unique<Impl>(host, port)) {}

RendererClient::~RendererClient() = default;
RendererClient::RendererClient(RendererClient&&) noexcept = default;
RendererClient& RendererClient::operator=(RendererClient&&) noexcept = default;

RendererStatus RendererClient::submit(const CommandStream& commands) {
    return impl_->submit(commands);
}

RendererStatus RendererClient::uploadMesh(std::uint8_t handle, const Mesh& mesh) {
    CommandStream commands;
    commands.uploadMesh(handle, mesh);
    return impl_->upload(commands);
}

RendererStatus RendererClient::drawMesh(std::uint32_t frameId,
                                        std::uint8_t handle,
                                        const Mat4& transform) {
    CommandStream commands;
    commands.beginFrame(frameId);
    commands.drawMesh(handle, transform);
    commands.endFrame();
    return submit(commands);
}

void sendUdp(const std::string& host, std::uint16_t port,
             const CommandStream& commands) {
    RendererClient client(host, port);
    static_cast<void>(client.submit(commands));
}

}
