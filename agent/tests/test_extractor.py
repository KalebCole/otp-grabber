import unittest

from agent.otp_grabber.extractor import decode_attributed_body, extract_code


def typedstream_body(text: str, *, boxed: bool = False) -> bytes:
    payload = text.encode("utf-8")
    length = (
        b"\x81" + len(payload).to_bytes(2, "little")
        if boxed
        else bytes([len(payload)])
    )
    return (
        b"prefixNSString\x01\x95\x84\x01+"
        + length
        + payload
        + b"\x86\x84\x02trailing"
    )


class ExtractCodeTests(unittest.TestCase):
    def test_extracts_explicit_numeric_code(self):
        self.assertEqual(
            extract_code("Security code", "Your security code is: 552146."),
            "552146",
        )

    def test_extracts_explicit_alphanumeric_code(self):
        self.assertEqual(
            extract_code("", "Your verification code is A1B2C3."),
            "A1B2C3",
        )

    def test_extracts_code_before_sms_context(self):
        self.assertEqual(
            extract_code("", "G-583920 is your Google verification code."),
            "583920",
        )

    def test_ignores_digits_in_url_query(self):
        body = (
            "Confirm your one-time payment at "
            "https://example.test/pay?messagetypecode=paysch&errortemplateid=1022"
        )
        self.assertIsNone(extract_code("Payment scheduled", body))

    def test_ignores_dates(self):
        self.assertIsNone(
            extract_code(
                "Confirm your appointment",
                "Your one-time appointment is scheduled for 08/12/2026.",
            )
        )

    def test_ignores_street_addresses_and_zip_codes(self):
        body = (
            "This is a one time offer. Use your rewards today. "
            "Michaels Stores, 3939 West John Carpenter Freeway, Irving TX 75063."
        )
        self.assertIsNone(extract_code("Rewards confirmation", body))

    def test_ignores_numeric_order_ids(self):
        self.assertIsNone(
            extract_code(
                "Order confirmation",
                "Enter your order #482013 to track it. Confirmation below.",
            )
        )

    def test_ignores_alphanumeric_confirmation_ids(self):
        self.assertIsNone(
            extract_code(
                "Payment confirmation",
                "One-time payment received. Confirmation number: U064L599.",
            )
        )

    def test_ignores_sequential_digits(self):
        self.assertIsNone(
            extract_code("", "Your verification code is 123456.")
        )


class DecodeAttributedBodyTests(unittest.TestCase):
    def test_decodes_single_byte_length_without_leaking_length_character(self):
        text = (
            "You have a Parcel Pending! Access code: 93754447. "
            "Location: Kiosk B."
        )
        self.assertEqual(decode_attributed_body(typedstream_body(text)), text)

    def test_decodes_boxed_little_endian_length(self):
        text = "X" * 40 + " your verification code is 552146 " + "Y" * 100
        self.assertEqual(
            decode_attributed_body(typedstream_body(text, boxed=True)),
            text,
        )

    def test_returns_empty_text_for_malformed_typedstream(self):
        self.assertEqual(decode_attributed_body(b"not a typedstream body"), "")


if __name__ == "__main__":
    unittest.main()
