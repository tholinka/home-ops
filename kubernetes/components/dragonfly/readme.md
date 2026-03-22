# Dragonfly mTLS

## Usage

- use `app-template` to auto-mount the secrets to app-template
- use `helm-stunnel` to auto inject stunnel sidecar
- use `app-template-stunnel` to do both of the above
- use `manual` for manual mounting
- use secret inside `manual` if the app can handle directly connecting without stunnel

## Reminders

- `fsGroup` is very important, or the app can't read the secrets
