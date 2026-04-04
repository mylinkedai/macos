adb -s 38261FDJG001D1 shell "ls /sdcard/DCIM/Camera/*.mp4" | while read f; do adb -s 38261FDJG001D1 pull "$f"; done
