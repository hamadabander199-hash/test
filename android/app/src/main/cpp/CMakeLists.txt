cmake_minimum_required(VERSION 3.22.1)
project("camzone")

# تحديد المعمارية والمسارات
set(lib_DIR "${CMAKE_CURRENT_SOURCE_DIR}/jniLibs/${ANDROID_ABI}")


# 1. تعريف مكتبة crypto
add_library(crypto STATIC IMPORTED)
set_target_properties(crypto PROPERTIES IMPORTED_LOCATION "${lib_DIR}/libcrypto.a")

# 2. تعريف مكتبة ssl
add_library(ssl STATIC IMPORTED)
set_target_properties(ssl PROPERTIES IMPORTED_LOCATION "${lib_DIR}/libssl.a")

# 3. إنشاء المكتبة الخاصة بك
add_library(native-lib SHARED native-lib.cpp)

# 5. تحديد مجلد الـ includes
# تأكد إن المسار بيشير للمجلد اللي جواه فولدر openssl
target_include_directories(native-lib PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
# 6. الربط النهائي
# رتبت المكتبات بحيث الـ ssl تنادي الـ crypto والـ log والـ z في الآخر
target_link_libraries(native-lib
        ssl
        crypto
        log
        z
        dl
        atomic)