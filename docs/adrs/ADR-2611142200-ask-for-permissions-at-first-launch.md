# ADR-2611142200: Ask for the microphone and Accessibility when Earshot first opens

**Status:** Accepted
**Date:** 2026-11-14
**Drivers:** After the bundle ID changed (ADR-2611142000) the owner found Earshot missing from System
Settings → Device Control and Data Access, and the Accessibility prompt kept opening on every dictation.
The owner's rule: "that has to happen during install". A permission is asked for when Earshot is set up,
not discovered later by hunting through System Settings.

## Decision

1. **Recordings opens with a "Set up Earshot" card** until the microphone is allowed and Dictation is
   either allowed or set aside. It sits under the model download card, so first launch is one screen.
   - **Microphone:** Allow asks macOS. If it was refused, Open Settings goes to the Microphone list.
   - **Dictation:** Turn On switches Dictation on and asks for Accessibility, which puts Earshot in the
     list. The row then says to switch Earshot on there, with Open Settings, and ticks itself as soon as
     macOS reports it (checked every second while the card shows; no relaunch). Not Now sets it aside;
     Settings → Dictation still offers it.
2. **The Accessibility prompt is shown at most once per launch.** A dictation without the permission puts
   the text on the clipboard and says so, without opening the system dialog again.
3. **Reset and allow relaunches Earshot** after clearing the entry, because macOS does not show the prompt
   twice to one process; the new process asks, and Earshot appears in the list again.
4. `SetupChecklist` is the pure rule for what each row shows; the card renders it.

## Gate

`SetupChecklistTests` pass in `Tests/run.sh`, the `setup-card` scenes render at the real width and at 380 pt,
and `DictationService` prompts through a once-per-launch guard.
