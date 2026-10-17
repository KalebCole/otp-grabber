# Personal release signing

Tagged GitHub releases require one self-signed **Code Signing** identity. This
repository's public certificate SHA-1 fingerprint is pinned in `identity.sha1`;
the corresponding encrypted GitHub Actions secrets are configured. Routine
releases reuse that identity. The certificate's private key must never be
committed.

If setting up a different repository or deliberately replacing a lost identity:

1. On a Mac, open **Keychain Access → Certificate Assistant → Create a
   Certificate**. Choose **Self Signed Root** for Identity Type and **Code
   Signing** for Certificate Type. Keep this identity for every future release.
2. Under **My Certificates**, export the identity **with its private key** as a
   password-protected `.p12`. Keep a separate encrypted backup of that file and
   its password outside GitHub. A newly generated certificate will not have the
   same code identity.
3. Run `openssl pkcs12 -in /path/to/identity.p12 -nokeys | openssl x509 -noout -fingerprint -sha1`
   and copy the certificate's 40-character SHA-1 fingerprint. The command asks
   for the `.p12` password. With GitHub CLI authenticated to this repo,
   run `scripts/setup-personal-signing.sh /path/to/identity.p12 FINGERPRINT`.
   The script saves the `.p12` and password as encrypted repository secrets and
   writes the public fingerprint to `signing/identity.sha1`.
4. Commit and push `signing/identity.sha1`. Only then create the next `v*` tag.
   The release workflow imports the identity into a temporary runner keychain,
   trusts its public certificate for code signing on that disposable runner,
   signs the app, checks its certificate and bundle identity, then deletes the
   temporary keychain. GitHub discards the runner after the job. The release
   fails if the identity is missing or mismatched.

The `.p12` is ignored by Git. GitHub Actions secrets are repository settings,
not Git-tracked files; the encrypted backup is needed if those settings are lost.
Normal development builds remain ad hoc signed. They must not be installed over
the personal release app if retaining Full Disk Access is the goal.

This personal signature is not Apple Developer ID and cannot be notarized. It
may require **Open Anyway** in System Settings on a Mac that downloads it. The
first switch from the previous ad hoc signature may also need a new Full Disk
Access grant. Test two consecutive signed releases before treating permission
retention as verified.
