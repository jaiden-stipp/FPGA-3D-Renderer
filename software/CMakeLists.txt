add_library(fpga_renderer src/renderer.cpp src/udp_transport.cpp)
target_include_directories(fpga_renderer PUBLIC include)
target_compile_features(fpga_renderer PUBLIC cxx_std_17)
if(WIN32)
    target_link_libraries(fpga_renderer PUBLIC ws2_32)
endif()

add_executable(renderer_example examples/basic_scene.cpp)
target_link_libraries(renderer_example PRIVATE fpga_renderer)

add_executable(renderer_udp_demo examples/ethernet_demo.cpp)
target_link_libraries(renderer_udp_demo PRIVATE fpga_renderer)

add_executable(renderer_tests tests/renderer_tests.cpp)
target_link_libraries(renderer_tests PRIVATE fpga_renderer)
add_test(NAME renderer_tests COMMAND renderer_tests)
