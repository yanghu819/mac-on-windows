# Magic Trackpad PTP report format (AmtPtp "Mt2" descriptor)

Observed on: `Apple USB Precision Touchpad Device (User-mode)`, Magic Trackpad USB-C 2024,
Windows 11 26200. Report length **112 bytes**, `ReportID = 0x05`.

```
offset        size  field
0             1     ReportID = 0x05
1 + 21*i      21    contact i  (i = 0..4)
108           1     ContactCount
109           2     MechanicalForce (sum of contact pressures, little endian)
111           1     Button (physical click), bit0
```

Contact layout (21 bytes):

```
+0   1   flags: bit0 = Confidence, bit1 = TipSwitch (1 = finger down)
+1   4   ContactID (uint32 LE) — stable while the finger stays down
+5   2   X (uint16 LE), logical range 0..7612
+7   2   Y (uint16 LE), logical range 0..5065
+9   2   Width
+11  2   Height
+13  2   Pressure
+15  6   Size, TouchMajor, TouchMinor, Orientation, Finger, State (vendor page 0xFF00)
```

Notes:

- Unused contacts keep `TipSwitch = 0` and zero coordinates; always filter on the tip bit, not only on `ContactCount`.
- Contacts may appear/disappear between frames; match by `ContactID` to compute motion. Averaging deltas of matched
  contacts is what makes “lift one finger mid-drag” seamless.
- The descriptor declares a fixed five contact slots — the report is always 112 bytes, never variable.
- The same report also drives Windows' own PTP stack; do not write to the device, only read `WM_INPUT`.

Decoding example (three fingers):

```
raw: 05 03 0B 00 00 00 ...  (count byte = 03 at offset 108)
c0: tip=True id=1   x=4471 y=2321
c1: tip=True id=2   x=3637 y=3032
c2: tip=True id=10  x=5612 y=2556
```

If a fork or another driver changes the descriptor (for example adds/removes fields), the offsets above no longer
apply — re-derive them from the INF/descriptor, or read the report descriptor with
`IOCTL_HID_GET_REPORT_DESCRIPTOR` (0x000B0000) on the device interface path.
