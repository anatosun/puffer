# pcm_player

PCM output for the Sendspin player of Puffer: a ring buffer of interleaved 16-bit frames played by [miniaudio](https://miniaud.io) on Android, iOS and Linux. It reports the ring position the device last read and when, on a monotonic clock, so playback can be scheduled against server timestamps.
