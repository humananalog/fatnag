#!/usr/bin/env python3
"""Reference check for Mi Scale 2 (XMTZC05HM) 13-byte frame decode.

Mirrors TheScale/TheScale/BLE/MiScale2FrameDecoder.swift so CI / Linux VMs
can validate protocol math without Xcode. Not a substitute for on-device BLE.
"""

from __future__ import annotations


def decode(data: bytes):
    if len(data) != 13:
        raise ValueError(f"wrong length {len(data)}")
    c0, c1 = data[0], data[1]
    is_lbs = (c0 & 0x01) != 0
    has_imp = (c1 & 0x02) != 0
    stable = (c1 & 0x20) != 0
    is_catty = (c1 & 0x40) != 0
    removed = (c1 & 0x80) != 0
    if not stable:
        raise ValueError("not stabilized")
    if removed:
        raise ValueError("weight removed")
    weight_raw = data[11] | (data[12] << 8)
    if is_lbs:
        weight_kg = (weight_raw / 100.0) * 0.45359237
        unit = "pound"
    elif is_catty:
        weight_kg = (weight_raw / 100.0) * 0.5
        unit = "catty"
    else:
        weight_kg = weight_raw / 200.0
        unit = "kilogram"
    impedance = None
    if has_imp:
        impedance = data[9] | (data[10] << 8)
        if impedance == 0 or impedance >= 3000:
            raise ValueError(f"invalid impedance {impedance}")
    return weight_kg, impedance, unit


def main() -> None:
    # 70.00 kg, 500 Ω, stabilized + impedance
    frame = bytearray(13)
    frame[0] = 0x02
    frame[1] = 0x22
    frame[2], frame[3] = 0xE8, 0x07  # 2024
    frame[9], frame[10] = 0xF4, 0x01  # 500
    frame[11], frame[12] = 0xB0, 0x36  # 14000
    kg, ohms, unit = decode(bytes(frame))
    assert abs(kg - 70.0) < 0.001, kg
    assert ohms == 500, ohms
    assert unit == "kilogram", unit

    bad = bytearray(frame)
    bad[1] = 0x02  # not stable
    try:
        decode(bytes(bad))
        raise SystemExit("expected not stabilized")
    except ValueError as exc:
        assert "not stabilized" in str(exc)

    print("validate_decode.py: OK")


if __name__ == "__main__":
    main()
