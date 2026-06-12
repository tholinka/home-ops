# Dragonfly mTLS

## Usage

- use `app-template` to auto-mount the secrets to app-template + `manual`
- use `helm-tunnel` to auto inject dfguard tunnel sidecar
- use `app-template-tunnel` to do both of the above
- use `manual` for manual mounting
- use secret inside `manual` if the app can handle directly connecting without dfguard tunnel

## Reminders

- `fsGroup` is very important, or the app can't read the secrets
