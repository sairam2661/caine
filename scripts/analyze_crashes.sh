echo "=== Crashes found ==="
find /data/saiva/caine/workdir/crashes.* -type f 2>/dev/null | wc -l
ls /data/saiva/caine/workdir/crashes.*/

echo "=== Corpus shards (fuzzing continued building these after the crash) ==="
ls -lh /data/saiva/caine/workdir/corpus.*

echo "=== Coverage reached despite crash ==="
tail -5 /data/saiva/caine/workdir/coverage-report-opt_crash_fuzzer_centipede.000000.final.txt