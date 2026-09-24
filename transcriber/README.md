# MajorTom — calls

Live German transcription of a call, click a word, get it translated and saved.
Saved words land in the same SQLite file the [MajorTom desktop app](../desktop)
reads, so they appear under its **Calls** tab.

A separate project from the [extension](../extension) on purpose: this captures
audio and talks to a local model, which the browser extension never needs to do.

## The flow

**On the Mac.** Start the call, then start a session and name the other person.
The app captures their voice from whichever app is playing audio and
transcribes it on device; your own side is not captured. The transcript scrolls
on screen. Click a word and it is written to the database with its sentence;
the library app translates it afterwards. End the session and the transcript is deleted. Only the
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

What is kept, all of it:

- each word or phrase you click, with the sentence around it — cut to at most
  ten words either side, since the recognizer often leaves out the punctuation
  that would end a sentence;
- the other person's name and the date, to group the words by conversation;
- on the phone, the same, in a small file until it is sent to the Mac.

Nothing else is written: no transcript, no audio, no logs. The translation
model is sent only the word and that one sentence.

## State

| Piece | Status |
|-------|--------|
| German transcription, on device | works |
| Mic capture (phone only) | works |
| Other party's audio (process tap) | works |
| Writing to the MajorTom database | works |
| Click-to-translate, local model | works |
| The window | used on a real WhatsApp call |
| iPhone app | runs on an iPhone 15 Plus |
| Sync over local wifi | works — discovery and round trip both verified |

```bash
./build.sh && open "build/MajorTom Calls.app"
```

```bash
swift run Probe --translate        # both translators, timed
swift run Probe --list             # what is playing, and everything tappable
swift run Probe --tap 60           # whatever app is playing, for 60s
swift run Probe --tap Signal 60    # a named app instead
swift run Probe --file clip.aiff   # a file, paced at 1x
swift run Probe 30                 # the mic
swift run Probe --db               # database write path, no audio
swift run Probe --serve            # the Mac end of the phone sync
swift run Probe --discover         # browse for it, as the phone does
swift run Probe --sync Ana         # find the Mac and send it words
```

`MAJORTOM_DB` points at a different SQLite file — always use it when testing, so
experiments do not land in the real library. Left unset, it resolves `data/` at
the repo root, the same file the desktop app reads.

## Translation

Two providers, because they fail in opposite directions.

**Apple's `Translation.framework`** is the floor: on-device, free, no server, and
fast enough to feel instant. It is also context-blind — it translates a word
without knowing how it was used, so `anziehen` is "to put on" whether the
speaker meant a coat or prices rising. It needs its German language pack
installed, which is a System Settings step; without it there is simply no fast
first answer.

**Any OpenAI-compatible endpoint** is the ceiling — LM Studio, llama.cpp,
Unsloth, Ollama. One HTTP client, not one integration each. It gets the sense
that was actually used, and the dictionary form worth filing.

A click saves the word immediately with no translation, then both providers run
in the background and fill it in. So a dead model, a cold model or no model at
all costs you a translation and never the word. Nothing in this path touches the
audio pipeline.

### Field names beat prompts

Under grammar-constrained decoding, what the JSON fields are *called* matters
more than the instructions. Asking for `sentence` got the German echoed back
untranslated and stray tokens leaked into `meaning`:

```
meaning:  to divert / to dissuade from something (in this context: ... ) own context: ...
sentence: Sie hat sich nicht davon abbringen lassen.      ← not translated
```

Renaming them `english_meaning` and `english_sentence` fixed it outright, same
model, same prompt:

```
english_meaning:  to divert / to deter
english_sentence: She didn't let herself be diverted from it.
```

### Thinking is worth the wait

Measured on Gemma 4 26B A4B via llama.cpp. Both modes get the *context* right —
neither said "to put on clothes" for the price sense — but only the thinking one
returns a form you would want in a vocabulary list:

| word (context) | reasoning on | reasoning off |
|---|---|---|
| `angezogen` (prices rose) | to rise / to increase | risen / increased |
| `aufgegeben` (posted a parcel) | to post | dropped off |
| latency | 7–15s | 2s |

So reasoning stays on by default. It runs in the background, so the latency is
invisible; "dropped off" in your library is not. Settings has the toggle.

A cold llama.cpp with `--sleep-idle-seconds` has to load the model before it
answers anything, which took 24s here. Hence the 180s request timeout.

## The phone

`phone/` is an iPhone app for the same thing in person: one microphone, tap
words as they come up, sync to the Mac afterwards. It has no model and no
database — words go over untranslated and the Mac fills them in.

It sits under `transcriber/` rather than beside it because it shares `CallCore`
with the Mac through a relative package path. `Database` and `Session` are
macOS-only inside that package; the sync payload and client are shared, so both
ends of the protocol live in one file.

### Which recognizer the phone gets

`SpeechTranscriber` is gated on hardware and Apple publishes no device list.
From their documentation:

> **isAvailable** — "A Boolean value that indicates whether this module is
> available given the device's hardware and capabilities."
>
> **DictationTranscriber** — "similar to system dictation features and
> compatible with older devices."
>
> "Use the [`isAvailable`] properties to see if the current device supports the
> speech-to-text models used by [`SpeechTranscriber`]. If it does not, consider
> disabling the feature or using [`DictationTranscriber`] instead."

So the app asks at launch and takes whichever it can get. The setup screen says
which one it chose, because that is the only way to find out for a given phone.
A simulator cannot answer it — it runs on the Mac's hardware, so it reports
whatever the Mac supports.

### Getting it onto a phone

```bash
cd phone && ./install-phone.sh
```

Builds, signs and installs. Also the weekly chore: a free Apple account's
provisioning profile lasts **seven days**, after which the app stops launching
until this is run again. Nothing about the app causes that — it is a property of
the account, and no amount of EU sideloading changes it. The DMA opened up
*distribution*, not code signing, and AltStore PAL wants a paid account anyway.
Paying the $99/year is the only thing that turns seven days into a year.

First install on a given phone needs two one-off steps: Developer Mode on
(Settings → Privacy & Security), which needs a restart to take effect, and then
trusting the certificate under Settings → General → VPN & Device Management.

**Turn any VPN off first.** It blocks the tunnel `devicectl` opens to the phone,
and the error it produces — "The tunnel connection failed" — says nothing about
VPNs. The device shows as `paired` but `disconnected`, which reads like a cable
or pairing fault and is not.

### Two Info.plist keys that fail silently

Bonjour browsing on iOS needs `NSLocalNetworkUsageDescription` *and*
`NSBonjourServices` listing the service type up front. Without them the browser
starts, reports no error, and finds nothing for ever.

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
      Transcriber.swift      one recognizer over one audio track
      MicSource.swift        the phone's microphone
      ProcessTapSource.swift their voice, tapped from the call app
      Session.swift          one call; transcript stays in memory
      Translator.swift       Apple translation + any OpenAI-compatible endpoint
      Settings.swift         endpoint config; the API key lives in the keychain
      Database.swift         writes into the desktop app's SQLite file
    MajorTomCalls/
      MajorTomCallsApp.swift window + menu bar item
      SessionModel.swift     bridges audio threads to the main actor
      TranscriptView.swift   clickable words, saved-word list
      SettingsView.swift     endpoint, model, and a Test that really translates
    Probe/           CLI smoke tests, no UI in the way
  build.sh           assembles the .app — needed for the TCC prompts
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
