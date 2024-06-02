# CMake project file for BootUtils library.

add_library(BootUtils STATIC)

target_sources(BootUtils PUBLIC     "${BOOT_INCLUDE}/BootUtils.hpp"
                         PRIVATE    "CollectionTools.hpp"
                                    "CollectionTools.cpp"
                                    "MemoryMap.cpp"
                                    "MemoryMap.hpp"
                                    "Heap.cpp"
                                    "Heap.hpp")

target_include_directories(BootUtils PUBLIC "${BOOT_INCLUDE}")

if (TEST_BUILD)

    add_executable(Test_BootUtils   Test_TargetTools.cpp
                                    Test_TargetTools.hpp
                                    Test_Sort.cpp
                                    Test_MemoryMap.cpp)

    target_link_libraries(Test_BootUtils PRIVATE GTest::GTest
                                                 GTest::Main
                                                 BootUtils)

    gtest_discover_tests(Test_BootUtils)
else()
    
endif()