# Guest And External MVP Rollout

## Profile: MvpMinimal

Policies included when `-GuestProfile MvpMinimal` is used:

- `CA-BL-011` Require MFA for Guests and External Users
- `CA-BL-012` Block Legacy Authentication for Guests and External Users

## Notes

- Both policies remain optional and disabled by default in JSON.
- The profile explicitly includes them for deployment/evaluation runs.
- `CA-BL-010` (Terms of Use) is intentionally excluded from this MVP profile.
