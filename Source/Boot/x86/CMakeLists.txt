# CMake project file for x86/x64 boot loader.

if (TEST_BUILD)
    # Create a unit test executable for loader-specific algorithms.
    add_executable(Test_Loader   Test_IsoImage.cpp)

    target_link_libraries(Test_Loader PRIVATE GTest::GTest
                                              GTest::Main
                                              BootUtils)

    gtest_discover_tests(Test_Loader)

else()
    # Compile/assemble the 16-bit and 32-bit loader code.
    add_executable(Loader16 Loader16.S)
    target_include_directories(Loader16 PRIVATE "${BOOT_INCLUDE}")
    target_compile_definitions(Loader16 PRIVATE "__ASM__"
                                                "NEEDS_IO_SEGMENT")
    target_link_options(Loader16 PRIVATE    "-Wl,--oformat=binary,-Ttext=0x0000")

    add_executable(Loader32 Entry32.S Main.cpp)
    target_include_directories(Loader32 PRIVATE "${BOOT_INCLUDE}")
    target_link_libraries(Loader32 PRIVATE BootUtils)
    target_compile_options(Loader32 PRIVATE -Wall -Wextra
                                            -Wpedantic
                                            -Wshadow)
    target_link_options(Loader32 PRIVATE "-Wl,--oformat=binary,-Ttext=0x100000")

    # Shared properties
    set_target_properties(Loader16 Loader32
                          PROPERTIES "SUFFIX" ".sys")

    # Append the 32-bit loader to the 16-bit loader to create a single file.
    set(BootSysFile "Boot.sys")
    cmake_path(APPEND BootSysPath "${CMAKE_CURRENT_BINARY_DIR}" "${BootSysFile}")

    add_custom_target(BootSys       ALL
                      COMMENT       "Create bare-metal boot loader"
                      BYPRODUCTS    "${BootSysPath}"
                      DEPENDS       $<TARGET_FILE:Loader16> $<TARGET_FILE:Loader32>
                      COMMAND       "${CMAKE_COMMAND}" -E cat $<TARGET_FILE:Loader16>
                                    $<TARGET_FILE:Loader32> $<ANGLE-R> "${BootSysPath}")

    # Annotate the custom target with file name and path.
    set_target_properties(BootSys PROPERTIES TARGET_FILE "${BootSysFile}"
                                             TARGET_PATH "${BootSysPath}")
endif()
