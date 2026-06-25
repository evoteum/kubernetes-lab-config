# itsbeginningtolookalotlikechristmas tunnel

Manages the Cloudflare Zero Trust tunnel and DNS record for
[itsbeginningtolookalotlikechristmas](https://github.com/evoteum/itsbeginningtolookalotlikechristmas)
via Crossplane.

## Before first sync

### 1. Cloudflare API token (one-time platform-level secret)

Required permissions: `Zone: DNS: Edit`, `Zero Trust: Edit`, `Account Settings: Read`.

```shell
bao kv put secret/cloudflare/api-token api_token=<token>
```

### 2. Tunnel secret

A random 32-byte value encoded as base64. Cloudflare uses this to authenticate the tunnel.
Generate and store it once — rotate only if the tunnel is compromised.

```shell
bao kv put secret/itsbeginningtolookalotlikechristmas/cloudflare-tunnel-secret \
  secret=$(openssl rand 32 | base64)
```

### 3. Fill in the placeholders in `environmentconfig-cloudflare.yaml`

These values live in `platform/control-plane/crossplane/environmentconfig-cloudflare.yaml`
and are shared by all tunnel Compositions, so fill them in once for the whole cluster.

| Placeholder               | Where to find it                               |
|---------------------------|------------------------------------------------|
| `<CLOUDFLARE_ACCOUNT_ID>` | Cloudflare dashboard URL or Account Settings   |
| `<CLOUDFLARE_ZONE_ID>`    | Cloudflare dashboard → zone → Overview sidebar |

The same zone ID is also needed in `chart/values.yaml` (`cloudflare.zoneId`) in the
[itsbeginningtolookalotlikechristmas](https://github.com/evoteum/itsbeginningtolookalotlikechristmas)
repo for the TXT records. The Composition automatically wires the tunnel UUID into the
tunnel config and CNAME, no `<TUNNEL_ID>` placeholder required.

## After first sync

Once Crossplane has created the tunnel, retrieve the tunnel token and store it in OpenBao.
The Composition automatically wires the tunnel UUID into the tunnel config and CNAME DNS
record — no manual tunnel ID step required.

### Tunnel token (for cloudflared pods)

Crossplane does not expose the tunnel token. Retrieve it via the CLI:

```shell
cloudflared tunnel token itsbeginningtolookalotlikechristmas
```

Store it in OpenBao so the `ExternalSecret` in the app chart can sync it to the cluster:

```shell
bao kv put secret/itsbeginningtolookalotlikechristmas/cloudflare-tunnel token=<tunnel_token>
```

This is a one-time step per tunnel. Only needs repeating if the tunnel is deleted and recreated.
