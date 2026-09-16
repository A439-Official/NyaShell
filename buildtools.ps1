tovenv


$builddir = "./tools"

if (-not (Test-Path $builddir)) {
    mkdir $builddir
}


g++ -O2 -std=c++17 -o $builddir/get_colors.exe ./tools/get_colors.cpp

nuitka --remove-output --standalone --onefile ./tools/load_image.py --output-dir=$builddir
