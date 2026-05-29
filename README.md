# macbook-display

A tiny macOS CLI for disabling and re-enabling the MacBook built-in
display for the current login session.

It uses public CoreGraphics APIs for display detection and a runtime lookup of
the private `CGSConfigureDisplayEnabled` symbol for the actual toggle.

## Safety

`disable` refuses to run unless a connected external display is detected.

`enable` is intentionally simpler: it reads the built-in display id saved by the
last successful `disable` and re-enables that display. It does not require an
external display, because enabling the built-in panel is the recovery path.

The display configuration is committed with `CGConfigureOption.forSession`, so
logging out or rebooting should clear the change.

## Build

```sh
swift build -c release
```

The release binary will be at:

```sh
.build/release/macbook-display
```

## Usage

```sh
macbook-display
macbook-display status
macbook-display disable
macbook-display enable
```

Running without arguments is the same as `status`.
