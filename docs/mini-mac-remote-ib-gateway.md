# IB Gateway on `mini-mac-remote`

`mini-mac-remote` is the configuration label for the remote profile. It does not
rename the Mac, user, or SSH account.

## Installation

Homebrew currently provides `ibkr`, but that cask is **IBKR Desktop**, not IB
Gateway. `trader-workstation` is Trader Workstation (TWS), also not IB Gateway.
Neither is a valid substitute for Gateway.

IBKR does not currently publish a maintained Homebrew cask for IB Gateway. Do
not add either of those casks to the remote profile. Install Gateway manually
from IBKR's official download page instead:

- <https://www.interactivebrokers.com/en/trading/ibgateway-latest.php>

The Homebrew cask catalog currently lists IBKR Desktop's Apple Silicon artifact
and supported macOS versions, but that is evidence about `ibkr` only, not about
Gateway. The remote Nix profile targets `aarch64-darwin`; select the official
IB Gateway macOS installer appropriate for that machine.

This manual install is intentionally outside Home Manager ownership. The
existing `camilo-remote` rebuild remains the source of truth for the machine's
managed packages and does not install, launch, or authenticate a broker client.

## Readiness and authentication

Installation alone does not make broker connectivity or trading ready. Before
running an API client or trading workflow:

1. Launch IB Gateway and complete the normal IBKR login and any required MFA.
2. Confirm the API listener is enabled and that the intended client can connect.
3. Confirm the session is authenticated and reconcile the trader's state before
   sending any orders.
4. If Gateway has restarted or its session has expired, repeat the normal
   authentication and connectivity checks. Do not weaken MFA or automate around
   an authentication challenge.

IBKR's official guidance describes daily and weekly reauthentication settings,
but this repository does not hardcode a restart day or time zone. Follow the
account's current IBKR settings and the applicable operational requirements:

- <https://www.interactivebrokers.com/docs/third-party-integrations/tws-settings/best-practice-configure-tws-ib-gateway/daily-weekly-reauthentication>

No installer, service startup, login, trading action, or reset is performed by
this change.
