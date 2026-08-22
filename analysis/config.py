import os
from pathlib import Path

ROOT = Path(__file__).parent
FIXTURES = ROOT / "fixtures"
OUT = ROOT / "out"

# uniswap v3 USDC/WETH 0.05% on mainnet. deepest arb flow of any pool, which is
# what we need to see the two populations separate.
POOL = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"
TOKEN0 = {"symbol": "USDC", "decimals": 6}
TOKEN1 = {"symbol": "WETH", "decimals": 18}

SWAP_TOPIC = "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67"

# post-merge mainnet blocks are a fixed 12s, so weighting by block number is
# the same as weighting by time
BLOCK_SECONDS = 12

# Locked by the drift-vs-null gate in analysis/out/gate.json. K_BLOCKS is only
# the equivalent for this 12-second mainnet fixture; deployments convert the
# time window to their own block time.
BASE_FEE_BPS = 5
ESCROW_FEE_BPS = 25
K_SECONDS = 120
K_BLOCKS = round(K_SECONDS / BLOCK_SECONDS)
THETA_BPS = 10
MIN_SWAP_USD = 100  # below this the amount ratio is noise, see fetch findings


def rpc_url() -> str:
    url = os.environ.get("MAINNET_RPC_URL", "").strip()
    if not url:
        raise SystemExit(
            "MAINNET_RPC_URL is not set.\n"
            "  export MAINNET_RPC_URL=https://mainnet.infura.io/v3/<your-key>\n"
            "or put it in analysis/.env"
        )
    return url


def load_dotenv():
    f = ROOT / ".env"
    if not f.exists():
        return
    for line in f.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
