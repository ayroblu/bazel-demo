Call harness
============

Runs the call transport with no UI, so two processes on one Mac can call each
other and no second device is needed. The microphone is replaced by a 440Hz
tone and the speaker by a byte counter, so neither end needs audio hardware or
a screen. Run each in its own terminal, callee first:

```sh
bazel run //local-call-app/harness -- --name mac-b --role callee
bazel run //local-call-app/harness -- --name mac-a --role caller
```

The caller invites the first peer it finds, the callee accepts, and both exit
after `--seconds` (15 by default, which is enough for anything but a slow
leak). The caller exits 0 if the call lasted that long and 1 if it dropped
first, so it can be scripted.

Both sides log a stats line every 5 seconds:

```
harness stats uptime=13s peers=1 out=387kB open=true dropped=0kB in=387kB
  open=true inEvents=160 sinceSend=0.1s sinceReceive=0.1s recv=387kB
  rate=30.6kB/s longestGap=0.1s
```

* `out` and `in` should climb together at about 31kB/s, the 16kHz mono Int16
  rate. `in` falling behind `out` means audio is being lost.
* `inEvents` counts stream read events. If it stops climbing while `out` does
  not, the receiver has gone deaf and the audio is silently dead.
* `dropped` is audio shed to keep the delay bounded, `longestGap` is the worst
  silence seen.

This covers discovery, invites, the session, both audio streams and the
disconnect path. It does not cover the audio engine, routing or the UI, which
still need real devices.
