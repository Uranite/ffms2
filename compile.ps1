#Requires -Version 5.1

<#
Script for compiling static ffms2 and its dependencies with Clang.
This script compiles somewhat minimal FFmpeg only for video/image decode.
The goal is to compile for FFVship and svt-av1.

Dependencies:
- Visual Studio C++ Build Tools (https://visualstudio.microsoft.com/visual-cpp-build-tools/)
- Clang/LLVM toolchain (https://github.com/llvm/llvm-project)
- MSYS2 (https://www.msys2.org/, path: C:\msys2, install base-devel in base msys2 (MSYS2 MSYS))
- Git (https://git-scm.com/)
- CMake (https://github.com/kitware/cmake)
- Ninja (https://github.com/ninja-build/ninja)
- Meson (https://github.com/mesonbuild/meson or pip install meson)
- NASM (https://www.nasm.us/)
- pkgconf (https://github.com/pkgconf/pkgconf)
Note that there might be other dependencies that I missed.

This script installs everything to C:\dev, you may change this below.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PREFIX = "C:\dev"

# For ffmpeg it's extra-cflags and extra-cxxflags in Build-FFmpeg function.
$CFLAGS = "-flto -O3 -DNDEBUG -march=native"
$CXXFLAGS = "-flto -O3 -DNDEBUG -march=native"

$ForceRecompile = $true
$choice = Read-Host "Do you want to recompile everything? [Y/n]"
if ($choice -match '^[nN]') {
    $ForceRecompile = $false
}

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "[INFO] $Label..." -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] $Label failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
}

function Import-Vcvars {
    param([string]$VsPath)
    $vcvars = Join-Path $VsPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvars)) {
        Write-Host "[ERROR] vcvarsall.bat not found at $vcvars" -ForegroundColor Red
        exit 1
    }

    $vcvarsArgs = "x64"

    $envLines = cmd /c "`"$vcvars`" $vcvarsArgs > nul && set"
    foreach ($line in $envLines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $name = $matches[1]
            $val = $matches[2]
            if ($name -ieq 'INCLUDE' -or $name -ieq 'LIB' -or $name -ieq 'LIBPATH') {
                Set-Item "env:$name" $val
            }
            elseif ($name -ieq 'PATH') {
                $env:PATH = $val
            }
        }
    }
}

function Build-Zlib {
    if (-not $ForceRecompile -and (Test-Path "$PREFIX\lib\zs.lib")) {
        Write-Host "[INFO] zlib already compiled. Skipping..." -ForegroundColor Cyan
    }
    else {
        if (Test-Path 'zlib') { Push-Location zlib; git reset --hard; git clean -xfd; git pull; Pop-Location }
        else { git clone --depth 1 https://github.com/madler/zlib.git }
        Push-Location zlib
        Invoke-Step "Building zlib" {
            cmake --fresh -B build -G Ninja -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_C_FLAGS_RELEASE="$CFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX"
            cmake --build build
            cmake --install build
        }
        Pop-Location
    }
}

function Build-Dav1d {
    if (-not $ForceRecompile -and (Test-Path "$PREFIX\lib\dav1d.lib")) {
        Write-Host "[INFO] dav1d already compiled. Skipping..." -ForegroundColor Cyan
    }
    else {
        if (Test-Path 'dav1d') { Push-Location dav1d; git reset --hard; git clean -xfd; git pull; Pop-Location }
        else { git clone --depth 1 https://code.videolan.org/videolan/dav1d.git }
        Push-Location dav1d
        Invoke-Step "Building dav1d" {
            meson setup --reconfigure build --prefix="$PREFIX" --default-library=static --buildtype=release -Db_vscrt=mt -Db_lto=true -Doptimization=3 -Denable_tools=false -Denable_examples=false -Dc_link_args="-fuse-ld=lld"
            meson install -C build
        }
        Pop-Location
        Move-Item "$PREFIX\lib\libdav1d.a" "$PREFIX\lib\dav1d.lib" -Force
    }
}

function Build-Libpng {
    if (-not $ForceRecompile -and (Test-Path "$PREFIX\lib\libpng*_static.lib")) {
        Write-Host "[INFO] libpng already compiled. Skipping..." -ForegroundColor Cyan
    }
    else {
        if (Test-Path 'libpng') { Push-Location libpng; git reset --hard; git clean -xfd; git pull; Pop-Location }
        else { git clone --depth 1 https://github.com/pnggroup/libpng.git }
        Push-Location libpng
        Invoke-Step "Building libpng" {
            cmake --fresh -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DZLIB_INCLUDE_DIR="$PREFIX\include" -DZLIB_LIBRARY="$PREFIX\lib\zs.lib" -DCMAKE_C_FLAGS_RELEASE="$CFLAGS" -DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_SHARED=OFF
            ninja -C build install
        }
        Pop-Location
    }
}

function Build-LibjpegTurbo {
    if (-not $ForceRecompile -and (Test-Path "$PREFIX\lib\jpeg-static.lib")) {
        Write-Host "[INFO] libjpeg-turbo already compiled. Skipping..." -ForegroundColor Cyan
    }
    else {
        if (Test-Path 'libjpeg-turbo') { Push-Location libjpeg-turbo; git reset --hard; git clean -xfd; git pull; Pop-Location }
        else { git clone --depth 1 https://github.com/libjpeg-turbo/libjpeg-turbo.git }
        Push-Location libjpeg-turbo
        Invoke-Step "Building libjpeg-turbo" {
            cmake --fresh -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_C_FLAGS_RELEASE="$CFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DENABLE_SHARED=OFF
            ninja -C build install
        }
        Pop-Location
    }
}

function Build-Libjxl {
    if (-not $ForceRecompile -and (Test-Path "$PREFIX\lib\jxl.lib")) {
        Write-Host "[INFO] libjxl already compiled. Skipping..." -ForegroundColor Cyan
    }
    else {
        if (Test-Path 'libjxl') { Push-Location libjxl; git reset --hard; git clean -xfd; git pull; Pop-Location }
        else { git clone --recursive --shallow-submodules https://github.com/libjxl/libjxl.git }
        Push-Location libjxl
        Invoke-Step "Building libjxl" {
            $libpngLib = Get-ChildItem "$PREFIX\lib\libpng*_static.lib" | Select-Object -First 1
            if (-not $libpngLib) {
                Write-Host "[ERROR] Could not find libpng static library in ext/lib" -ForegroundColor Red
                exit 1
            }
            # We should probably make a PR for this to the libjxl repo lol
            $jxlCondition = 'if(NOT MSVC AND NOT APPLE AND NOT (WIN32 AND CMAKE_C_COMPILER_ID MATCHES "Clang" AND NOT MINGW AND NOT MSYS))'
            
            if (Test-Path "lib\jxl.cmake") {
                (Get-Content "lib\jxl.cmake" -Raw) -replace 'if\(NOT MSVC AND NOT APPLE\)', $jxlCondition | Set-Content "lib\jxl.cmake" -NoNewline
            }
            if (Test-Path "lib\jxl_cms.cmake") {
                $cmsContent = Get-Content "lib\jxl_cms.cmake" -Raw
                $cmsPatch = "$jxlCondition`n    set(JPEGXL_CMS_PRIVATE_LIBS `"-lm `$`{PKGCONFIG_CXX_LIB`}`")`n  else()`n    set(JPEGXL_CMS_PRIVATE_LIBS `"`$`{PKGCONFIG_CXX_LIB`}`")`n  endif()"
                $cmsContent = $cmsContent -replace 'set\(JPEGXL_CMS_PRIVATE_LIBS "-lm \$\{PKGCONFIG_CXX_LIB\}"\)', $cmsPatch
                Set-Content "lib\jxl_cms.cmake" $cmsContent -NoNewline
            }
            if (Test-Path "lib\threads\libjxl_threads.pc.in") {
                (Get-Content "lib\threads\libjxl_threads.pc.in" -Raw) -replace 'Libs\.private: -lm', 'Libs.private: @JPEGXL_THREADS_LIBM@' | Set-Content "lib\threads\libjxl_threads.pc.in" -NoNewline
            }
            if (Test-Path "lib\jxl_threads.cmake") {
                $threadsContent = Get-Content "lib\jxl_threads.cmake" -Raw
                if ($threadsContent -notmatch 'JPEGXL_THREADS_LIBM') {
                    $threadsPatch = "$jxlCondition`n  set(JPEGXL_THREADS_LIBM `"-lm`")`nelse()`n  set(JPEGXL_THREADS_LIBM `"`")`nendif()`n`nconfigure_file"
                    $threadsContent = $threadsContent -replace 'configure_file', $threadsPatch
                    Set-Content "lib\jxl_threads.cmake" $threadsContent -NoNewline
                }
            }
            cmake --fresh -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DJPEGXL_STATIC=ON -DBUILD_TESTING=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_MANPAGES=OFF -DJPEGXL_ENABLE_OPENEXR=OFF -DJPEGXL_ENABLE_TCMALLOC=OFF -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_DOXYGEN=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF -DZLIB_INCLUDE_DIR="$PREFIX\include" -DZLIB_LIBRARY="$PREFIX\lib\zs.lib" -DPNG_PNG_INCLUDE_DIR="$PREFIX\include" -DPNG_LIBRARY="$($libpngLib.FullName)" -DJPEG_INCLUDE_DIR="$PREFIX\include" -DJPEG_LIBRARY="$PREFIX\lib\jpeg-static.lib" -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_C_FLAGS_RELEASE="$CFLAGS" -DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX"
            ninja -C build install
        }
        Pop-Location
    }
}


function Build-FFmpeg {
    param([string]$VsPath, [string]$MsysExe)
    
    $env:INCLUDE = "$PREFIX\include;$env:INCLUDE"
    $env:LIB = "$PREFIX\lib;$env:LIB"

    if (-not $ForceRecompile -and (Test-Path "$PREFIX\lib\avcodec.lib")) {
        Write-Host "[INFO] FFmpeg already compiled. Skipping..." -ForegroundColor Cyan
    }
    else {
        if (Test-Path 'FFmpeg') { Push-Location FFmpeg; git checkout n8.1.2; git reset --hard; git clean -xfd; git pull; Pop-Location }
        else { git clone --depth 1 -b n8.1.2 https://github.com/FFmpeg/FFmpeg.git }
        Push-Location FFmpeg
        Invoke-Step "Building FFmpeg" {
            $bashScript = @'
#!/bin/sh
set -e
UNIX_PREFIX="$(cygpath -u '@@PREFIX@@')"
export PKG_CONFIG_PATH="$UNIX_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

sed -i 's/if test "$cc_type" = "clang"; then/if true; then/' configure
sed -i 's/test "$cc_type" != "$ld_type" && die "LTO requires same compiler and linker"/true/' configure
# sed -i 's/-L\*) \[ "$_flags_type" = "link" \] && echo -libpath:${flag#-L} ;;/-L*) [ "$_flags_type" = "link" ] \&\& echo -libpath:${flag#-L} ;; -I*) [ "$_flags_type" = "link" ] || echo $flag ;;/g' configure
# Don't treat lld-link warnings as link failure 🤤
sed -i "s/grep -qE 'LNK4044|lld-link: warning: ignoring unknown argument'/false/" configure
sed -i 's/echo zlib.lib ;;/echo zs.lib ;;/' configure
./configure \
    --prefix="$UNIX_PREFIX" \
    --cc="clang-cl" \
    --cxx="clang-cl" \
    --ld="lld-link" \
    --ar="llvm-ar" \
    --ranlib="llvm-ranlib" \
    --nm="llvm-nm" \
    --strip="llvm-strip" \
    --toolchain="msvc" \
    --enable-lto="full" \
    --extra-cflags="-flto -DNDEBUG -march=native /clang:-O3" \
    --extra-cxxflags="-flto -DNDEBUG -march=native /clang:-O3" \
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
    --disable-debug \
    --disable-decoders \
    --enable-decoder=aasc,agm,aic,alias_pix,amv,anm,ansi,apng,apv,arbc,argo,asv1,asv2,aura,aura2,avrn,avrp,avs,avui,bethsoftvid,bfi,bintext,bitpacked,bmp,bmv_video,brender_pix,c93,cavs,cdgraphics,cdtoons,cdxl,cfhd,cinepak,clearvideo,cljr,cllc,cpia,cri,cscd,cyuv,dds,dfa,dirac,dnxhd,dpx,dsicinvideo,dvvideo,dxa,dxtory,dxv,escape124,escape130,exr,ffv1,ffvhuff,fic,fits,flashsv,flashsv2,flic,fmvc,fraps,frwu,g2m,gdv,gem,gif,h261,h263,h263i,h263p,h264,hap,hdr,hevc,hq_hqa,hqx,huffyuv,hymt,idcin,idf,iff_ilbm,imm4,imm5,indeo2,indeo3,indeo4,indeo5,ipu,jpeg2000,jpegls,jv,kgv1,kmvc,lagarith,lead,loco,lscr,m101,magicyuv,mdec,media100,mimic,mjpeg,mjpegb,mmvideo,mobiclip,motionpixels,mpeg1video,mpeg2video,mpeg4,msa1,mscc,msmpeg4v1,msmpeg4v2,msmpeg4v3,msp2,msrle,mss1,mss2,msvideo1,mszh,mts2,mv30,mvc1,mvc2,mvdv,mvha,mwsc,mxpeg,notchlc,nuv,paf_video,pam,pbm,pcx,pdv,pfm,pgm,pgmyuv,pgx,phm,photocd,pictor,pixlet,png,ppm,prores,prores_raw,prosumer,psd,ptx,qdraw,qoi,qpeg,qtrle,r10k,r210,rasc,rawvideo,rl2,roq,roq_dpcm,rpza,rscc,rtv1,rv10,rv20,rv30,rv40,rv60,sanm,scpr,screenpresso,sga,sgi,sgirle,sheervideo,simbiosis_imx,smc,smvjpeg,snow,sp5x,speedhq,srgc,sunrast,svq1,svq3,targa,targa_y216,tdsc,theora,thp,tiertexseqvideo,tiff,tmv,truemotion1,truemotion2,truemotion2rt,tscc,tscc2,txd,ulti,utvideo,v210,v210x,vb,vble,vbn,vc1,vc1image,vcr1,vmdvideo,vmix,vmnc,vnull,vp3,vp4,vp5,vp6,vp6a,vp6f,vp7,vp8,vp9,vqc,vvc,wbmp,wcmv,webp,webp_anim,wmv1,wmv2,wmv3,wmv3image,wnv1,wrapped_avframe,xan_wc3,xan_wc4,xbin,xbm,xface,xpm,xwd,y41p,ylc,yop,yuv4,zerocodec,zlib,zmbv,libdav1d,libjxl,libjxl_anim \
    --disable-encoders \
    --disable-muxers \
    --disable-filters \
    --disable-avfilter \
    --disable-devices \
    --disable-hwaccels \
    --enable-libdav1d \
    --enable-libjxl \
    --enable-zlib
make -j$(nproc)
make install
'@
            $bashScript = $bashScript -replace '@@PREFIX@@', $PREFIX
            Set-Content -Path 'build_ffmpeg.sh' -Value $bashScript -Encoding Ascii
            $env:MSYS2_PATH_TYPE = 'inherit'
            $unixPath = $PWD.Path -replace '\\', '/'
            & $MsysExe -lc "cd `"$unixPath`" && sh ./build_ffmpeg.sh"
        }
        Pop-Location
    }
}

function Build-FFMS2 {
    Invoke-Step "Building ffms2" {
        $env:PKG_CONFIG_PATH = "$PREFIX/lib/pkgconfig;$env:PKG_CONFIG_PATH"
        cmake --fresh -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_C_FLAGS_RELEASE="$CFLAGS" -DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_VAPOURSYNTH=OFF -DENABLE_TOOLS=OFF -DZLIB_INCLUDE_DIR="$PREFIX\include" -DZLIB_LIBRARY="$PREFIX\lib\zs.lib"
        ninja -C build install
    }
}

$env:CC = 'clang'
$env:CXX = 'clang++'

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$msysExe = "C:\msys64\usr\bin\bash.exe"

if (-not (Test-Path "$PREFIX\lib")) { New-Item -ItemType Directory "$PREFIX\lib" -Force | Out-Null }

Import-Vcvars -VsPath $vsPath

Build-Zlib
Build-Dav1d
Build-Libpng
Build-LibjpegTurbo
Build-Libjxl
Build-FFmpeg -VsPath $vsPath -MsysExe $msysExe

Get-ChildItem "$PREFIX\lib\pkgconfig\*.pc" | ForEach-Object {
    $content = Get-Content $_.FullName
    $content = $content -replace '-libpath:', '-L'
    $content = $content -replace ' ([a-zA-Z0-9_\-]+)\.lib', ' -l$1'
    Set-Content $_.FullName $content
}

Build-FFMS2

Write-Host "[SUCCESS] Build script finished." -ForegroundColor Green
