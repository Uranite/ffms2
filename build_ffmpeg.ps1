#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "[INFO] $Label..." -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] $Label failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
}

$env:CC = 'clang'
$env:CXX = 'clang++'

$msysExe = "C:\msys64\usr\bin\bash.exe"
if (-not (Test-Path $msysExe)) {
    Write-Host "[ERROR] MSYS2 bash not found at $msysExe." -ForegroundColor Red
    exit 1
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) {
    Write-Host "[ERROR] Visual Studio with C++ tools not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path 'ext\lib')) { New-Item -ItemType Directory 'ext\lib' -Force | Out-Null }

# ============================================================
#  Compile zlib, dav1d, FFmpeg
# ============================================================

# zlib
if (Test-Path "ext\lib\zs.lib") {
    Write-Host "[INFO] zlib already compiled. Skipping..." -ForegroundColor Cyan
}
else {
    if (Test-Path 'zlib') { Push-Location zlib; git pull; Pop-Location }
    else { git clone --depth 1 https://github.com/madler/zlib.git }
    Push-Location zlib
    Invoke-Step "Building zlib" {
        cmake --fresh -S . -B zlib_build -G Ninja -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_C_FLAGS_RELEASE="-flto=thin -O3 -DNDEBUG -march=native" -DCMAKE_INSTALL_PREFIX="$PWD/../ext"
        cmake --build zlib_build
        cmake --install zlib_build
    }
    Pop-Location
}

# dav1d
if (Test-Path 'ext\lib\dav1d.lib') {
    Write-Host "[INFO] dav1d already compiled. Skipping..." -ForegroundColor Cyan
}
else {
    if (Test-Path 'dav1d') { Push-Location dav1d; git pull; Pop-Location }
    else { git clone --depth 1 https://code.videolan.org/videolan/dav1d.git }
    Push-Location dav1d
    Invoke-Step "Building dav1d" {
        meson setup build --default-library=static --buildtype=release -Db_vscrt=mt -Db_lto=true -Db_lto_mode=thin -Doptimization=3 -Denable_tools=false -Denable_examples=false -Dbitdepths="8,16" -Denable_asm=true "-Dc_args=-O3 -DNDEBUG -march=native -fuse-ld=lld" "-Dc_link_args=-O3 -DNDEBUG -march=native -fuse-ld=lld"
        ninja -C build
    }
    Pop-Location
    Copy-Item dav1d\build\src\libdav1d.a ext\lib\dav1d.lib -Force
}

$msvcLibPath = Get-ChildItem "$vsPath\VC\Tools\MSVC" |
Sort-Object Name -Descending | Select-Object -First 1 |
ForEach-Object { "$($_.FullName)\lib\x64" }

$candidateRoots = @(
    (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -Name KitsRoot10 -ErrorAction SilentlyContinue).KitsRoot10,
    "${env:ProgramFiles(x86)}\Windows Kits\10",
    "$env:ProgramFiles\Windows Kits\10"
)

$sdkRoot = $null
$sdkVersion = $null

foreach ($root in $candidateRoots) {
    if ($root -and (Test-Path $root)) {
        $foundVer = Get-ChildItem "$root\Lib" -ErrorAction SilentlyContinue | Where-Object { (Test-Path "$($_.FullName)\um\x64") -and (Test-Path "$($_.FullName)\ucrt\x64") } | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
        if ($foundVer) {
            $sdkRoot = $root
            $sdkVersion = $foundVer
            break
        }
    }
}

if (-not $sdkRoot -or -not $sdkVersion) {
    Write-Host "[ERROR] Could not find a valid Windows 10/11 SDK installation with um\x64 and ucrt\x64 libraries." -ForegroundColor Red
    exit 1
}

$sdkLibUm = "$sdkRoot\Lib\$sdkVersion\um\x64"
$sdkLibUcrt = "$sdkRoot\Lib\$sdkVersion\ucrt\x64"

if (-not (Test-Path $sdkLibUm)) { Write-Host "[ERROR] Windows SDK lib um\x64 not found at $sdkLibUm." -ForegroundColor Red; exit 1 }
if (-not (Test-Path $sdkLibUcrt)) { Write-Host "[ERROR] Windows SDK lib ucrt\x64 not found at $sdkLibUcrt." -ForegroundColor Red; exit 1 }
if (-not (Test-Path $msvcLibPath)) { Write-Host "[ERROR] MSVC lib not found at $msvcLibPath." -ForegroundColor Red; exit 1 }

$msvcLibPathShort = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($msvcLibPath).ShortPath
$sdkLibUmShort = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($sdkLibUm).ShortPath
$sdkLibUcrtShort = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($sdkLibUcrt).ShortPath
$msvcLibPathUnix = $msvcLibPathShort -replace '\\', '/'
$sdkLibUmUnix = $sdkLibUmShort -replace '\\', '/'
$sdkLibUcrtUnix = $sdkLibUcrtShort -replace '\\', '/'

# FFmpeg
if (Test-Path 'ext\lib\avcodec.lib') {
    Write-Host "[INFO] FFmpeg already compiled. Skipping..." -ForegroundColor Cyan
}
else {
    if (Test-Path 'FFmpeg') { Push-Location FFmpeg; git pull; Pop-Location }
    else { git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git }
    Push-Location FFmpeg
    Invoke-Step "Building FFmpeg" {
        $bashScript = @"
#!/bin/sh
set -e
export PKG_CONFIG_PATH="`$(pwd)/../dav1d/build/meson-private"
sed -i "s|^prefix=.*|prefix=`$(pwd)/../dav1d/build|" `$(pwd)/../dav1d/build/meson-private/dav1d.pc

sed -i 's/if test "`$cc_type" = "clang"; then/if true; then/' configure
sed -i 's/test "`$cc_type" != "`$ld_type" && die "LTO requires same compiler and linker"/true/' configure
./configure \
    --prefix="`$(pwd)/../ext" \
    --cc="clang-cl" \
    --cxx="clang-cl" \
    --ld="lld-link" \
    --ar="llvm-ar" \
    --ranlib="llvm-ranlib" \
    --nm="llvm-nm" \
    --strip="llvm-strip" \
    --toolchain="msvc" \
    --enable-lto="thin" \
    --extra-cflags="-flto=thin -DNDEBUG -march=native /clang:-O3 -I`$(pwd)/../dav1d/include -I`$(pwd)/../dav1d/build/include" \
    --extra-ldflags="-LIBPATH:`$(pwd)/../ext/lib \"-LIBPATH:$msvcLibPathUnix\" \"-LIBPATH:$sdkLibUmUnix\" \"-LIBPATH:$sdkLibUcrtUnix\"" \
    --extra-libs="dav1d.lib" \
    --disable-shared \
    --enable-static \
    --pkg-config-flags="--static" \
    --disable-programs \
    --disable-doc \
    --disable-htmlpages \
    --disable-manpages \
    --disable-podpages \
    --disable-txtpages \
    --disable-network \
    --disable-autodetect \
    --disable-all \
    --disable-everything \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
    --enable-swscale \
    --enable-swresample \
    --enable-protocol=file \
    --enable-demuxer=matroska \
    --enable-demuxer=mov \
    --enable-demuxer=mpegts \
    --enable-demuxer=mpegps \
    --enable-demuxer=flv \
    --enable-demuxer=avi \
    --enable-demuxer=ivf \
    --enable-demuxer=yuv4mpegpipe \
    --enable-demuxer=h264 \
    --enable-demuxer=hevc \
    --enable-demuxer=vvc \
    --enable-decoder=rawvideo \
    --enable-decoder=h264 \
    --enable-decoder=hevc \
    --enable-decoder=mpeg2video \
    --enable-decoder=mpeg1video \
    --enable-decoder=mpeg4 \
    --enable-decoder=av1 \
    --enable-decoder=libdav1d \
    --enable-decoder=vp9 \
    --enable-decoder=vc1 \
    --enable-decoder=vvc \
    --enable-decoder=aac \
    --enable-decoder=aac_latm \
    --enable-decoder=ac3 \
    --enable-decoder=eac3 \
    --enable-decoder=dca \
    --enable-decoder=truehd \
    --enable-decoder=mlp \
    --enable-decoder=mp1 \
    --enable-decoder=mp1float \
    --enable-decoder=mp2 \
    --enable-decoder=mp2float \
    --enable-decoder=mp3 \
    --enable-decoder=mp3float \
    --enable-decoder=opus \
    --enable-decoder=vorbis \
    --enable-decoder=flac \
    --enable-decoder=alac \
    --enable-decoder=ape \
    --enable-decoder=tak \
    --enable-decoder=tta \
    --enable-decoder=wavpack \
    --enable-decoder=wmalossless \
    --enable-decoder=wmapro \
    --enable-decoder=wmav1 \
    --enable-decoder=wmav2 \
    --enable-decoder=mpc7 \
    --enable-decoder=mpc8 \
    --enable-decoder=dsd_lsbf \
    --enable-decoder=dsd_lsbf_planar \
    --enable-decoder=dsd_msbf \
    --enable-decoder=dsd_msbf_planar \
    --enable-decoder=pcm_s16le \
    --enable-decoder=pcm_s16be \
    --enable-decoder=pcm_s24le \
    --enable-decoder=pcm_s24be \
    --enable-decoder=pcm_s32le \
    --enable-decoder=pcm_s32be \
    --enable-decoder=pcm_f32le \
    --enable-decoder=pcm_f32be \
    --enable-decoder=pcm_f64le \
    --enable-decoder=pcm_f64be \
    --enable-decoder=pcm_bluray \
    --enable-decoder=pcm_dvd \
    --enable-libdav1d \
    --enable-parser=h264 \
    --enable-parser=hevc \
    --enable-parser=mpeg4video \
    --enable-parser=mpegvideo \
    --enable-parser=av1 \
    --enable-parser=vp9 \
    --enable-parser=vvc \
    --enable-parser=vc1 \
    --enable-parser=aac \
    --enable-parser=ac3 \
    --enable-parser=dca \
    --enable-parser=mpegaudio \
    --enable-parser=opus \
    --enable-parser=vorbis \
    --enable-parser=flac \
    --enable-decoder=prores \
    --enable-decoder=dnxhd \
    --enable-decoder=ffv1 \
    --enable-decoder=mjpeg \
    --enable-decoder=png \
    --enable-demuxer=mxf \
    --enable-demuxer=image2 \
    --enable-demuxer=image2pipe \
    --enable-parser=mjpeg \
    --enable-parser=png \
    --enable-parser=dnxhd
make -j`$(nproc)
make install
"@
        Set-Content -Path 'build_ffmpeg.sh' -Value $bashScript -Encoding Ascii
        $env:MSYS2_PATH_TYPE = 'inherit'
        $unixPath = $PWD.Path -replace '\\', '/'
        & $msysExe -lc "cd `"$unixPath`" && sh ./build_ffmpeg.sh"
    }
    Pop-Location
}

Write-Host "Script finished successfully." -ForegroundColor Green
