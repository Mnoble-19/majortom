# MajorTom — calls

Live German transcription of a call, click a word, get it translated and saved.
Saved words land in the same SQLite file the [MajorTom desktop app](../desktop)
reads, so they appear under its **Calls** tab.

A separate project from the [extension](../extension) on purpose: this captures
audio and talks to a local model, which the browser extension never needs to do.

## The flow

**On the Mac.** Start a session and name the other person. The app captures two
audio tracks — their voice from whichever app is playing audio, your voice from
the mic — and transcribes both on device. The transcript scrolls on screen. Click a word: a
local LLM translates it together with the sentence it came from, and the pair is
written to the database. End the session and the transcript is deleted. Only the
words you saved survive.

**In person.** Same screen on the phone, but no model on the device, so words are
saved with their sentence and no translation. On sync the Mac fills the
translations in and writes them to the same database.

Nothing is stored that you did not click. There is no transcript table.

## Why the transcript is not saved

Two reasons, and the second is the real one. Conversations with friends are not
material to leave lying around in a plaintext database. And the value is in the
words you noticed, not in a wall of text you will never reread.

The cost is that review has to happen live, during the session. That is a
deliberate trade.

## State

| Piece | Status |
|-------|--------|
| German transcription, on device | works |
| Mic capture | works |
| Other party's audio (process tap) | works |
| Writing to the MajorTom database | works |
| Two tracks running as one session | built, not yet run on a real call |
| Click-to-translate, local LLM | not started |
| The window you actually use | not started |
| iOS app | not started |
| Sync over local wifi | not started |

```bash
swift run Probe --list             # what is playing, and everything tappable
swift run Probe --tap 60           # whatever app is playing, for 60s
swift run Probe --tap Signal 60    # a named app instead
swift run Probe --file clip.aiff   # a file, paced at 1x
swift run Probe 30                 # the mic
swift run Probe --db               # database write path, no audio
```

`MAJORTOM_DB` points at a different SQLite file — always use it when testing, so
experiments do not land in the real library. Left unset, it resolves `data/` at
the repo root, the same file the desktop app reads.

## Two things about SpeechTranscriber that cost a while

Both were found by probing, and neither is obvious from the API.

**`.fastResults` is not optional.** With only `.volatileResults`, the analyzer
reports *nothing* until the input stream is finalized — a whole call's audio
arrives at once, when the call is over. It looks like streaming works, because
the buffered results flush progressively at the end. It is not streaming. With
`.fastResults` the volatile text arrives about once a second, which is what the
live captions are made of.

**Lines commit on turn boundaries, and that is correct.** The recognizer only
finalizes a line after roughly 3.5 seconds of silence. That sounds far too long
for conversation — until you notice each track is silent that long whenever the
*other* person is talking. So lines land on turn boundaries by themselves.

Forcing them to commit sooner is a dead end. `SpeechAnalyzer.finalize(through:)`
truncates whatever phrase it cuts through:

```
settleDelay 0.4s →  "Sie hat sich nicht" / "abbringen lassen"     ← "davon" gone
                    "Ich finde das wirklich bemerken"             ← truncated
natural       →  "Sie hat sich nicht davon abbringen lassen."
```

Dropping words is the one thing this app cannot do — a dropped word is exactly
the word you were trying to save.

## Layout

```
mac/
  Sources/
    CallCore/
      Transcriber.swift      one recognizer per track
      MicSource.swift        your voice
      ProcessTapSource.swift their voice, tapped from the call app
      Session.swift          both tracks as one call; transcript stays in memory
      Database.swift         writes into the desktop app's SQLite file
    MajorTomCalls/   the SwiftUI app (a stub so far)
    Probe/           CLI smoke tests, no UI in the way
phone/               iOS app (not started)
```

## Notes on tapping

Nothing here knows about WhatsApp or Signal, and nothing needs to. A session
asks Core Audio which app is playing audio and taps that — on a call there is
normally exactly one answer, so there is nothing to pick and it makes no
difference which app the call is on. Naming an app explicitly is the fallback
for when several are making noise at once.

It taps **every process belonging to that app**, not one. Call apps are several
processes and the voice does not necessarily come out of the one you would name
— WhatsApp exposes `net.whatsapp.WhatsApp.ServiceExtension` beside the main app.
Tapping the group means never having to know which is which.

The tap is per app rather than system-wide, so a video playing in another window
stays out of the transcript. It does not mute anything; the call sounds normal.

Enumerating processes needs no permission. Creating a tap does — macOS asks once,
under Privacy & Security → Screen & System Audio Recording.
