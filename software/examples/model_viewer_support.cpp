#include "model_viewer_support.hpp"

#include <algorithm>
#include <iostream>
#include <stdexcept>

#ifdef _WIN32
#include <conio.h>
#else
#include <sys/select.h>
#include <termios.h>
#include <unistd.h>
#endif

namespace model_viewer {

namespace {

Control decodeKey(int value) {
    switch (value) {
        case 27:
        case 'x':
        case 'X': return Control::Quit;
        case 'a':
        case 'A': return Control::MoveLeft;
        case 'd':
        case 'D': return Control::MoveRight;
        case 'w':
        case 'W': return Control::MoveUp;
        case 's':
        case 'S': return Control::MoveDown;
        case 'q':
        case 'Q': return Control::MoveForward;
        case 'e':
        case 'E': return Control::MoveBackward;
        case '+':
        case '=': return Control::ScaleUp;
        case '-':
        case '_': return Control::ScaleDown;
        case ' ': return Control::ToggleAnimation;
        case 'r':
        case 'R': return Control::Reset;
        default: return Control::None;
    }
}

std::filesystem::path defaultModelPath(const char* executable) {
    const auto besideExecutable = std::filesystem::absolute(executable).parent_path() /
                                 "assets/low_poly_crystal.obj";
    if (std::filesystem::exists(besideExecutable))
        return besideExecutable;
    return "software/assets/low_poly_crystal.obj";
}

}

struct Keyboard::Impl {
#ifndef _WIN32
    termios original{};
    bool active = false;

    int readByte() const {
        if (!active)
            return -1;
        fd_set input;
        FD_ZERO(&input);
        FD_SET(STDIN_FILENO, &input);
        timeval timeout{};
        if (select(STDIN_FILENO + 1, &input, nullptr, nullptr, &timeout) <= 0)
            return -1;
        unsigned char value = 0;
        return read(STDIN_FILENO, &value, 1) == 1 ? value : -1;
    }
#endif
};

Keyboard::Keyboard() : impl_(std::make_unique<Impl>()) {
#ifndef _WIN32
    impl_->active = isatty(STDIN_FILENO) &&
                    tcgetattr(STDIN_FILENO, &impl_->original) == 0;
    if (impl_->active) {
        termios raw = impl_->original;
        raw.c_lflag &= static_cast<tcflag_t>(~(ICANON | ECHO));
        tcsetattr(STDIN_FILENO, TCSANOW, &raw);
    }
#endif
}

Keyboard::~Keyboard() {
#ifndef _WIN32
    if (impl_->active)
        tcsetattr(STDIN_FILENO, TCSANOW, &impl_->original);
#endif
}

Control Keyboard::poll() {
#ifdef _WIN32
    if (!_kbhit())
        return Control::None;
    int value = _getch();
    if (value == 0 || value == 224) {
        value = _getch();
        if (value == 75)
            return Control::YawLeft;
        if (value == 77)
            return Control::YawRight;
        if (value == 72)
            return Control::PitchUp;
        if (value == 80)
            return Control::PitchDown;
        return Control::None;
    }
    return decodeKey(value);
#else
    const int first = impl_->readByte();
    if (first < 0)
        return Control::None;
    if (first == 27) {
        const int second = impl_->readByte();
        if (second != '[')
            return Control::Quit;
        const int third = impl_->readByte();
        if (third == 'D')
            return Control::YawLeft;
        if (third == 'C')
            return Control::YawRight;
        if (third == 'A')
            return Control::PitchUp;
        if (third == 'B')
            return Control::PitchDown;
        return Control::None;
    }
    return decodeKey(first);
#endif
}

void applyControl(ViewerState& state, Control control) {
    switch (control) {
        case Control::YawLeft: state.yaw -= 0.10F; break;
        case Control::YawRight: state.yaw += 0.10F; break;
        case Control::PitchUp: state.pitch += 0.10F; break;
        case Control::PitchDown: state.pitch -= 0.10F; break;
        case Control::MoveLeft: state.x -= 0.12F; break;
        case Control::MoveRight: state.x += 0.12F; break;
        case Control::MoveUp: state.y += 0.12F; break;
        case Control::MoveDown: state.y -= 0.12F; break;
        case Control::MoveForward: state.z -= 0.12F; break;
        case Control::MoveBackward: state.z += 0.12F; break;
        case Control::ScaleUp: state.scale = (std::min)(3.0F, state.scale * 1.1F); break;
        case Control::ScaleDown: state.scale = (std::max)(0.1F, state.scale / 1.1F); break;
        case Control::ToggleAnimation: state.animate = !state.animate; break;
        case Control::Reset: state = ViewerState{}; break;
        case Control::Quit: state.quit = true; break;
        case Control::None: break;
    }
    state.x = (std::clamp)(state.x, -5.0F, 5.0F);
    state.y = (std::clamp)(state.y, -3.0F, 3.0F);
    state.z = (std::clamp)(state.z, -4.0F, 4.0F);
}

ViewerOptions parseOptions(int argc, char** argv) {
    ViewerOptions options;
    options.modelPath = defaultModelPath(argv[0]);
    int next = 1;
    if (next < argc && std::string(argv[next]) == "--help") {
        options.showHelp = true;
        return options;
    }
    if (next < argc && std::string(argv[next]) == "--inspect") {
        options.inspectOnly = true;
        ++next;
    }
    if (next < argc)
        options.modelPath = argv[next++];
    if (!options.inspectOnly && next < argc)
        options.address = argv[next++];
    if (!options.inspectOnly && next < argc) {
        const unsigned long value = std::stoul(argv[next++]);
        if (value > 65535)
            throw std::out_of_range("UDP port must be between 0 and 65535");
        options.port = static_cast<std::uint16_t>(value);
    }
    if (!options.inspectOnly && next < argc)
        options.frameLimit = std::stoi(argv[next++]);
    if (!options.inspectOnly && next < argc)
        options.instanceCount = std::stoul(argv[next++]);
    if (next != argc)
        throw std::invalid_argument("too many model viewer arguments");
    if (options.frameLimit < 0)
        throw std::invalid_argument("frame count cannot be negative");
    if (options.instanceCount > 8)
        throw std::out_of_range("instance count must be between 1 and 8, or 0 for automatic");
    return options;
}

void printControls() {
    std::cout << "Controls\n"
              << "  Arrow keys: rotate\n"
              << "  W/A/S/D: move vertically and horizontally\n"
              << "  Q/E: move toward or away from the camera\n"
              << "  +/-: scale\n"
              << "  Space: pause or resume automatic rotation\n"
              << "  R: reset the view\n"
              << "  X or Escape: exit\n\n";
}

void printUsage(const char* executable) {
    std::cout << "Usage:\n  " << executable
              << " [obj-file] [address] [port] [frames] [instances]\n  "
              << executable << " --inspect [obj-file]\n"
              << "frames defaults to 0 for an unlimited run. instances defaults\n"
              << "to 1 for large models and 3 for small models.\n";
}

}
