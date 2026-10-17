# Clipboard failure investigation

The checked-in Chrome manifest identifies version 0.1.0. The checked-in popup calls
`navigator.clipboard.writeText(record.code)` after its model has validated a nonempty
string. The Swift client decodes `code` as a string. This does not reproduce a literal
`undefined` clipboard write.

The installed Mac app and extension, `/v1/latest` response, and clipboard are not
available from this Linux workspace. Capture their versions and a redacted response
on the target Mac before assigning a cause. Replace codes and tokens in the capture
with labels of the same type and length. Record whether the selected `code` field is
missing, empty, malformed, or valid, and whether the clipboard changed.

The native client now validates immediately before copying. Empty values, a literal
`undefined`, and malformed values fail before the pasteboard is cleared.

## Redacted sample messages for native fixtures

| Kind | Subject or body | Expected |
| --- | --- | --- |
| Gmail code | `Your verification code is 483921` | Code `483921` |
| Messages code | `Use 741205 to sign in.` | Code `741205` |
| Non-code | `Order 483921 shipped today.` | No code |
| Reset link | `Reset your password: https://accounts.example.test/reset?token=abc123` | Reset link only |
| Empty | Empty subject and body | No finding |
| Malformed | `Your code is undefined` | No code |
