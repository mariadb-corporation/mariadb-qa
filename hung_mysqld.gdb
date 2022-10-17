set log on out.txt
set pagination off
set print pretty on
set print frame-arguments all
thread apply all bt
info threads
show scheduler-locking
show schedule-multiple
show non-stop
show target-async
