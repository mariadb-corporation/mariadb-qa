tar -hcf - . | XZ_OPT=-9e xz --verbose --stdout --threads 0 -2 > myarchive.tar.xz
# To extract:
# tar -xf myarchive.tar.xz -I 'xz --verbose --threads 0 -2'
# or
# XZ_OPT='--verbose --threads 0 -2' tar -xf myarchive.tar.xz

# Another option may be (ref https://unix.stackexchange.com/questions/608207/how-to-use-multi-threading-for-creating-and-extracting-tar-xz)
# tar -c -I 'xz -9e --verbose -T0' -f myarchive.tar.xz  # to compress
