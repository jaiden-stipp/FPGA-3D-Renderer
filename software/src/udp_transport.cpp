#include "fpga_renderer/renderer.hpp"

#include <memory>
#include <stdexcept>
#include <string>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace fpga_renderer {

namespace {

constexpr std::size_t maximumPayload = 1400;

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
    closesocket(socket);
}
#else
using Socket = int;
constexpr Socket invalidSocket = -1;

class SocketSystem {};

void closeSocket(Socket socket) {
    close(socket);
}
#endif

struct AddressDeleter {
    void operator()(addrinfo* address) const {
        if (address)
            freeaddrinfo(address);
    }
};

}

void sendUdp(const std::string& host, std::uint16_t port,
             const std::vector<std::uint8_t>& bytes) {
    if (bytes.empty())
        throw std::invalid_argument("cannot send an empty command stream");
    if (bytes.size() > maximumPayload)
        throw std::length_error("command stream exceeds the 1400-byte test transport limit");

    SocketSystem socketSystem;
    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_protocol = IPPROTO_UDP;
    addrinfo* rawAddresses = nullptr;
    const std::string service = std::to_string(port);
    const int lookupResult = getaddrinfo(host.c_str(), service.c_str(), &hints, &rawAddresses);
    if (lookupResult != 0)
        throw std::runtime_error("could not resolve UDP destination " + host);
    std::unique_ptr<addrinfo, AddressDeleter> addresses(rawAddresses);

    Socket socket = invalidSocket;
    addrinfo* destination = nullptr;
    for (addrinfo* address = addresses.get(); address; address = address->ai_next) {
        socket = ::socket(address->ai_family, address->ai_socktype, address->ai_protocol);
        if (socket != invalidSocket) {
            destination = address;
            break;
        }
    }
    if (socket == invalidSocket || !destination)
        throw std::runtime_error("could not create UDP socket");

#ifdef _WIN32
    const int sent = sendto(socket, reinterpret_cast<const char*>(bytes.data()),
                            static_cast<int>(bytes.size()), 0,
                            destination->ai_addr, static_cast<int>(destination->ai_addrlen));
#else
    const auto sent = sendto(socket, bytes.data(), bytes.size(), 0,
                             destination->ai_addr, destination->ai_addrlen);
#endif
    closeSocket(socket);
    if (sent < 0 || static_cast<std::size_t>(sent) != bytes.size())
        throw std::runtime_error("could not send the complete UDP command stream");
}

void sendUdp(const std::string& host, std::uint16_t port,
             const CommandStream& commands) {
    sendUdp(host, port, commands.bytes());
}

}
