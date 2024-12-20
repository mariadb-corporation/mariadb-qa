# w/ thanks https://unix.stackexchange.com/questions/608207/how-to-use-multi-threading-for-creating-and-extracting-tar-xz)
tar -c -I 'xz -9e --verbose -T0' -f myarchive.tar.xz .

# To extract fastly (both verified to work) (tar -xf myarchive.tar.xz also works but is much slower):
# tar -xf myarchive.tar.xz -I 'xz --verbose --threads 0 -2'
# or
# XZ_OPT='--verbose --threads 0 -2' tar -xf myarchive.tar.xz
