#include "fpga_renderer/renderer.hpp"
#include "protocol_codec.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>

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

constexpr std::size_t maximumChunkSize = protocol::maximumDatagramBytes -
                                         protocol::transportHeaderBytes;
constexpr auto busyDelay = std::chrono::milliseconds(10);

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
    explicit Impl(TransportOptions options) : options_(std::move(options)) {
        if (options_.host.empty())
            throw std::invalid_argument("UDP destination cannot be empty");
        if (options_.packetAttempts == 0)
            throw std::invalid_argument("packet attempt count must be positive");
        addrinfo hints{};
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_DGRAM;
        hints.ai_protocol = IPPROTO_UDP;
        addrinfo* rawAddresses = nullptr;
        const std::string service = std::to_string(options_.port);
        if (getaddrinfo(options_.host.c_str(), service.c_str(), &hints,
                        &rawAddresses) != 0)
            throw std::runtime_error("could not resolve UDP destination " + options_.host);
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
        throw std::runtime_error("could not connect UDP socket to " + options_.host);
    }

    ~Impl() {
        closeSocket(socket_);
    }

    FrameResult submit(const CommandStream& stream) {
        const auto& commands = stream.bytes();
        if (commands.empty())
            throw std::invalid_argument("cannot submit an empty command stream");
        const std::uint32_t frameId = stream.frameId();
        sendPackets(commands);

        const auto deadline = std::chrono::steady_clock::now() + options_.frameTimeout;
        while (std::chrono::steady_clock::now() < deadline) {
            detail::WireStatus status{};
            if (!receiveStatus(deadline - std::chrono::steady_clock::now(), status))
                break;
            if (status.event == StatusEvent::FrameDisplayed && status.id == frameId) {
                if (!status.hasStatistics)
                    throw std::runtime_error("frame completion did not include statistics");
                return {status.id, status.fifoFree, status.flags, status.statistics};
            }
        }
        throw std::runtime_error("timed out waiting for frame " +
                                 std::to_string(frameId) +
                                 " to be displayed. Verify that the FPGA SOF and "
                                 "C++ executable were rebuilt from the same protocol version");
    }

    PacketAcknowledgement upload(const CommandStream& stream) {
        if (stream.bytes().empty())
            throw std::invalid_argument("cannot upload an empty command stream");
        return sendPackets(stream.bytes());
    }

private:
    PacketAcknowledgement sendPackets(const std::vector<std::uint8_t>& commands) {
        const std::uint32_t submissionId = ++nextSubmissionId_;
        const std::size_t packetCount =
            (commands.size() + maximumChunkSize - 1) / maximumChunkSize;
        if (packetCount > 65536)
            throw std::length_error("command stream needs more than 65536 packets");

        for (std::size_t packetIndex = 0; packetIndex < packetCount; ++packetIndex) {
            const std::size_t offset = packetIndex * maximumChunkSize;
            const std::size_t size = (std::min)(maximumChunkSize, commands.size() - offset);
            const auto sequence = static_cast<std::uint16_t>(packetIndex);
            const auto packet = detail::makeTransportPacket(
                commands, offset, size, submissionId, sequence,
                packetIndex == 0, packetIndex + 1 == packetCount);
            lastPacketStatus_ = acknowledgePacket(packet, submissionId, sequence);
        }
        return lastPacketStatus_;
    }

    PacketAcknowledgement acknowledgePacket(const std::vector<std::uint8_t>& packet,
                                            std::uint32_t submissionId,
                                            std::uint16_t sequence) {
        for (unsigned attempt = 0; attempt < options_.packetAttempts; ++attempt) {
#ifdef _WIN32
            const int sent = ::send(socket_, reinterpret_cast<const char*>(packet.data()),
                                    static_cast<int>(packet.size()), 0);
#else
            const auto sent = ::send(socket_, packet.data(), packet.size(), 0);
#endif
            if (sent < 0 || static_cast<std::size_t>(sent) != packet.size())
                throw std::runtime_error("could not send a complete UDP packet");

            const auto deadline = std::chrono::steady_clock::now() +
                                  options_.packetTimeout;
            while (std::chrono::steady_clock::now() < deadline) {
                detail::WireStatus status{};
                if (!receiveStatus(deadline - std::chrono::steady_clock::now(), status))
                    break;
                if (status.event != StatusEvent::PacketAcknowledged ||
                    status.id != submissionId || status.sequence != sequence)
                    continue;
                if (status.flags & StatusBusy) {
                    std::this_thread::sleep_for(busyDelay);
                    break;
                }
                if ((status.flags & StatusAccepted) == 0)
                    throw std::runtime_error(packetError(status.flags));
                return {status.id, status.sequence, status.fifoFree, status.flags};
            }
        }
        throw std::runtime_error("timed out sending submission " +
                                 std::to_string(submissionId) +
                                 " packet " + std::to_string(sequence));
    }

    template <typename Rep, typename Period>
    bool receiveStatus(std::chrono::duration<Rep, Period> timeout,
                       detail::WireStatus& status) {
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
        return detail::decodeStatusPacket(response.data(),
                                          static_cast<std::size_t>(received),
                                          status);
    }

    TransportOptions options_;
    SocketSystem socketSystem_;
    Socket socket_ = invalidSocket;
    std::uint32_t nextSubmissionId_ = static_cast<std::uint32_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
    PacketAcknowledgement lastPacketStatus_{};
};

RendererClient::RendererClient(TransportOptions options)
    : impl_(std::make_unique<Impl>(std::move(options))) {}

RendererClient::RendererClient(std::string host, std::uint16_t port)
    : RendererClient(TransportOptions{std::move(host), port}) {}

RendererClient::~RendererClient() = default;
RendererClient::RendererClient(RendererClient&&) noexcept = default;
RendererClient& RendererClient::operator=(RendererClient&&) noexcept = default;

FrameResult RendererClient::submit(const CommandStream& commands) {
    return impl_->submit(commands);
}

PacketAcknowledgement RendererClient::uploadMesh(std::uint8_t handle, const Mesh& mesh) {
    CommandStream commands;
    commands.uploadMesh(handle, mesh);
    return impl_->upload(commands);
}

FrameResult RendererClient::drawMesh(std::uint32_t frameId,
                                     std::uint8_t handle,
                                     const Mat4& transform) {
    CommandStream commands;
    commands.beginFrame(frameId);
    commands.drawMesh(handle, transform);
    commands.endFrame();
    return submit(commands);
}

}
