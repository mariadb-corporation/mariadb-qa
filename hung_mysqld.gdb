set trace-commands on
set logging file out.txt
set logging enabled on
set pagination off
set print pretty on
set print frame-arguments all
thread apply all bt
info threads
show scheduler-locking
show schedule-multiple
show non-stop
show mi-async
display/i $pc
disassemble
info reg
print buf_pool
set logging enabled off
