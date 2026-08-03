"""Precision-first verification-code extraction shared by all sources."""

from __future__ import annotations

import re


_OTP_KEYWORDS = (
    "verification code",
    "verify code",
    "verification",
    "code is",
    "your code",
    "security code",
    "one-time",
    "one time",
    "otp",
    "2fa",
    "two-factor",
    "two factor",
    "authentication code",
    "login code",
    "sign-in code",
    "signin code",
    "confirm",
    "passcode",
    "pin code",
    "access code",
)

_STRONG_CONTEXT = (
    "verification code",
    "your code",
    "code is",
    "otp",
    "one-time",
    "one time",
    "passcode",
    "security code",
    "authentication code",
    "login code",
    "sign-in code",
    "confirmation code",
    "pin code",
    "access code",
)

_WEAK_CONTEXT = ("code", "enter", "use", "verify", "submit", "input", "type")

_URL_RE = re.compile(r"https?://\S+|www\.\S+|\S+\?[\w%=&.+-]{8,}", re.I)

_CANDIDATE_PATTERNS = (
    (
        re.compile(
            r"(?:code|otp|pin|passcode)\s*(?:is|:)\s*:?\s*"
            r"([A-Z0-9]{4,8}|\d{3}[-\s]\d{3})",
            re.I,
        ),
        15,
    ),
    (re.compile(r"\b(\d{3}[-\s]\d{3})\b"), 3),
    (re.compile(r"\b(\d{4,8})\b"), 3),
    (re.compile(r"\b([A-Z0-9]{4,8})\b", re.I), 0),
)

_EXCLUDED_SPANS = (
    re.compile(r"\+?\d{1,3}[-.\s]?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"),
    re.compile(r"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"),
    re.compile(r"\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?", re.I),
    re.compile(r"\b(?:19|20)\d{2}\b"),
    re.compile(
        r"(?:order|ref|reference|tracking|invoice|po|#)\s*[:#]?\s*"
        r"[A-Z0-9][A-Z0-9-]{3,}",
        re.I,
    ),
    re.compile(
        r"(?:confirmation|reference|order|tracking|account|member|customer|"
        r"policy|claim|case|ticket|receipt|transaction|reservation|booking|"
        r"itinerary)\s*(?:number|num|no|id|#)?\s*"
        r"(?:is|of|=|:|#)?\s*[:.#=]?\s*[A-Z0-9][A-Z0-9-]{3,}",
        re.I,
    ),
    re.compile(r"\b[A-Z]{2}\s+\d{5}(?:-\d{4})?\b", re.I),
    re.compile(r"\b\d{5}-\d{4}\b"),
    re.compile(r"\$\d+(?:\.\d{2})?"),
    re.compile(r"\b\d{9,}\b"),
    re.compile(
        r"\b\d{2,6}\s+(?:north|south|east|west|n|s|e|w|"
        r"[A-Z][a-z]+\s+(?:st|street|ave|avenue|blvd|boulevard|rd|road|"
        r"dr|drive|ln|lane|way|ct|court|pl|place|pkwy|parkway|fwy|freeway|"
        r"hwy|highway|suite|ste|floor|fl))\b",
        re.I,
    ),
)


def _is_sequential(value: str) -> bool:
    if not value.isdigit():
        return False
    digits = [int(character) for character in value]
    ascending = all(
        current == previous + 1
        for previous, current in zip(digits, digits[1:])
    )
    descending = all(
        current == previous - 1
        for previous, current in zip(digits, digits[1:])
    )
    return ascending or descending


def _is_excluded(text: str, raw: str, clean: str) -> bool:
    if re.fullmatch(r"(\d)\1+", clean) or _is_sequential(clean):
        return True
    for pattern in _EXCLUDED_SPANS:
        if any(
            raw.lower() in match.group(0).lower()
            for match in pattern.finditer(text)
        ):
            return True
    return False


def _context_score(text: str, start: int, end: int) -> int:
    lowered = text.lower()
    strong_window = lowered[max(0, start - 80):end + 48]
    if any(keyword in strong_window for keyword in _STRONG_CONTEXT):
        return 2
    weak_window = lowered[max(0, start - 20):end + 20]
    if any(keyword in weak_window for keyword in _WEAK_CONTEXT):
        return 1
    return 0


def extract_code(subject: str = "", body: str = "") -> str | None:
    """Return the best human-entered verification code, if one is explicit."""
    clean_subject = _URL_RE.sub(" ", subject or "")
    clean_body = _URL_RE.sub(" ", body or "")
    text = f"{clean_subject} {clean_body}"
    lowered = text.lower()
    if not any(keyword in lowered for keyword in _OTP_KEYWORDS):
        return None

    candidates: dict[str, tuple[int, int]] = {}
    for pattern, pattern_score in _CANDIDATE_PATTERNS:
        for match in pattern.finditer(text):
            raw = match.group(1)
            clean = re.sub(r"[-\s]", "", raw).upper()
            if re.fullmatch(r"[A-Z]+", clean):
                continue
            if _is_excluded(text, raw, clean):
                continue
            context = _context_score(text, match.start(1), match.end(1))
            score = context * 10 + pattern_score
            if raw.lower() in clean_subject.lower():
                score += 5
            previous = candidates.get(clean)
            if previous is None or score > previous[0]:
                candidates[clean] = (score, context)

    if not candidates:
        return None
    code, (score, context) = max(
        candidates.items(),
        key=lambda item: item[1][0],
    )
    return code if context >= 1 or score >= 15 else None


def decode_attributed_body(blob: bytes | None) -> str:
    """Decode the NSString payload in a Messages typedstream body."""
    if not blob:
        return ""
    marker_start = blob.find(b"NSString")
    if marker_start < 0:
        return ""
    marker = blob.find(b"+", marker_start + len(b"NSString"), marker_start + 16)
    if marker < 0 or marker + 1 >= len(blob):
        return ""

    length_position = marker + 1
    first = blob[length_position]
    if first == 0x81:
        if length_position + 3 > len(blob):
            return ""
        length = int.from_bytes(
            blob[length_position + 1:length_position + 3],
            "little",
        )
        payload_start = length_position + 3
    else:
        length = first
        payload_start = length_position + 1

    payload = blob[payload_start:payload_start + length]
    if len(payload) != length:
        return ""
    return payload.decode("utf-8", errors="replace")
