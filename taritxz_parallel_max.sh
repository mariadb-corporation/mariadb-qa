tar -hcf - . | XZ_OPT=-9e xz --verbose --stdout --threads 0 -2 > myarchive.tar.xz
