# Custom i3blocks bandwidth block

![demo](.demo.gif)

A customizable bandwidth monitor for i3blocks written in Zig.

## Features

- Monitor network interface bandwidth (Rx/Tx)
- Support for bits/s and bytes/s output
- Configurable warning and critical thresholds with color output
- SI units support
- Multiple interface monitoring
- Configurable refresh rate

## Building

Requires Zig 0.13 or later.

```shell
zig build
zig-out/bin/bandwidth -h
```

The binary is:

```shell
zig-out/bin/bandwidth
```

Copy it to a directory in your path for easy access:

```shell
cp zig-out/bin/bandwidth ~/.local/bin
```

Or if you prefer, let zig install it in your home directory (assuming `~/.local/bin` is in your `$PATH`):

```shell
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

`bandwidth` is a single statically linked binary. No further runtime files are required.
You may install it on another system by simply copying the binary.
It can be cross compiled to other platforms using zig's `-Dtarget`

```shell
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-linux
zig build -Dtarget=arm-linux
```

## Installation

1. Build the binary
2. Copy it to your i3blocks scripts directory (typically `~/.config/i3blocks/scripts/`)
3. Make it executable: `chmod +x ~/.config/i3blocks/scripts/bandwidth`

## Configuration

Add to your i3blocks configuration:

```ini
[bandwidth]
command=$SCRIPT_DIR/bandwidth
interval=persist
markup=pango
label=
min_width=20000.0 B/s 20000.0 B/s
color=#000
```

## Flags

```
    -b, --bits
            use bits/s

    -B, --bytes
            use bytes/s (default)

    -t, --seconds <usize>
            refresh time (default is 1)

    -i, --interfaces <string>
            interfaces to monitor, comma separated (default all except lo)

    -w, --warning <string>
            set warning (default orange) for Rx:Tx bandwidth

    -W, --warningcolor <string>
            set warning color (#RRGGBB)

    -c, --critical <string>
            set critical (default red) for Rx:Tx bandwidth

    -C, --criticalcolor <string>
            set critical color (#RRGGBB)

    -s, --si
            use SI units (default is IEC)

    -h, --help
            print this help message
```

## Example Output

```
<span fallback='true' color='#FF7373'>1.0KB/s</span> <span fallback='true'>5.0 B/s</span>
<span fallback='true' color='#FF7373'>8.0MB/s</span> <span fallback='true' color='#FF7373'>2.7KB/s</span>
```

## License

MIT
