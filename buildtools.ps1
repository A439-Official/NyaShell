tovenv


$builddir = "./tools"

if (Test-Path $builddir) {
    Remove-Item -LiteralPath $builddir -Recurse -Force
}
mkdir $builddir


g++ -O2 -std=c++17 -o $builddir/get_colors.exe ./toolssrc/get_colors.cpp

nuitka --remove-output --standalone --onefile ./toolssrc/show_image.py --output-dir=$builddir
