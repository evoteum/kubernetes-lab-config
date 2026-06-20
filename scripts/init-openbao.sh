#!/usr/bin/env bash
# One-time OpenBao bootstrap: initialise the cluster, join follower pods to
# the raft cluster, and unseal every pod.
# This cannot be done via GitOps -- see README.md#openbao-initialisation.
#
# Safe to re-run on its own (e.g. after a pod restart) by answering "n" when
# asked whether to run init -- already-joined/unsealed pods are skipped.
set -uo pipefail

NAMESPACE="openbao"
PODS=(openbao-0 openbao-1 openbao-2)
LEADER="${PODS[0]}"
LEADER_ADDR="http://${LEADER}.openbao-internal.${NAMESPACE}.svc.cluster.local:8200"

bao_status() {
  kubectl exec -n "$NAMESPACE" "$1" -- bao status 2>&1
}

status_field() {
  # $1 = bao status output, $2 = field name (must be the first column token)
  echo "$1" | awk -v f="$2" '$1 == f {print $2}'
}

# A just-unsealed (especially just-joined) follower can take a few seconds to
# catch up via raft before its own status flips to Sealed: false. Poll briefly
# instead of treating a single immediate check as final.
wait_until_unsealed() {
  local pod="$1" attempt status sealed
  for attempt in $(seq 1 10); do
    status=$(bao_status "$pod")
    sealed=$(status_field "$status" "Sealed")
    [[ "$sealed" == "false" ]] && return 0
    sleep 1
  done
  return 1
}

read -rp "Run 'bao operator init' now? Only do this once, ever. [yes/N] " do_init
if [[ "$do_init" == "yes" ]]; then
  echo
  echo ">>> Save every line of this output somewhere safe and offline."
  echo ">>> Losing the unseal keys and root token after this point makes"
  echo ">>> everything in OpenBao permanently unrecoverable."
  echo
  if ! kubectl exec -n "$NAMESPACE" "$LEADER" -- bao operator init; then
    echo "ERROR: 'bao operator init' failed on $LEADER. Aborting." >&2
    exit 1
  fi
  echo
  read -rp "Press enter once you've saved the keys and root token. "
fi

echo
echo "Enter 3 of the 5 unseal keys (input hidden):"
keys=()
for i in 1 2 3; do
  read -rsp "  Key $i: " key
  echo
  keys+=("$key")
done

failures=0

for pod in "${PODS[@]}"; do
  echo
  echo "--- $pod ---"
  status=$(bao_status "$pod")
  initialized=$(status_field "$status" "Initialized")
  sealed=$(status_field "$status" "Sealed")

  if [[ "$initialized" != "true" ]]; then
    if [[ "$pod" == "$LEADER" ]]; then
      echo "ERROR: $pod (the leader) is not initialised. Run init first." >&2
      failures=$((failures + 1))
      continue
    fi

    echo "Not yet joined to the raft cluster -- joining via $LEADER..."
    if ! kubectl exec -n "$NAMESPACE" "$pod" -- \
        bao operator raft join -- "$LEADER_ADDR" >/dev/null; then
      echo "ERROR: $pod failed to join the raft cluster." >&2
      failures=$((failures + 1))
      continue
    fi
    echo "Joined."

    status=$(bao_status "$pod")
    sealed=$(status_field "$status" "Sealed")
  fi

  if [[ "$sealed" != "true" ]]; then
    echo "Already unsealed, nothing to do."
    continue
  fi

  echo "Unsealing..."
  unseal_ok=true
  for key in "${keys[@]}"; do
    if ! kubectl exec -n "$NAMESPACE" "$pod" -- \
        bao operator unseal -- "$key" >/dev/null; then
      echo "ERROR: an unseal key was rejected by $pod." >&2
      unseal_ok=false
      break
    fi
  done

  if [[ "$unseal_ok" != "true" ]]; then
    failures=$((failures + 1))
    continue
  fi

  if wait_until_unsealed "$pod"; then
    echo "Unsealed."
  else
    echo "ERROR: $pod still sealed 10s after submitting all 3 keys." >&2
    failures=$((failures + 1))
  fi
done

echo
kubectl get pods -n "$NAMESPACE"

if [[ "$failures" -gt 0 ]]; then
  echo
  echo "$failures pod(s) failed -- see errors above." >&2
  exit 1
fi

echo
echo "All pods initialised, joined, and unsealed."

# ── One-time OpenBao configuration ────────────────────────────────────────────
echo
read -rp "Run one-time OpenBao configuration (KV engine, auth method, ESO role)? [yes/N] " do_config
[[ "$do_config" != "yes" ]] && exit 0

read -rsp "Root token: " root_token
echo

# Run a bao command inside the leader pod, authenticated as root.
run_bao() {
  kubectl exec -n "$NAMESPACE" "$LEADER" -- \
    env VAULT_TOKEN="$root_token" bao "$@"
}

# KV v2 secrets engine at secret/
echo
if run_bao secrets list -format=json 2>/dev/null | grep -q '"secret/"'; then
  echo "KV v2 secrets engine already mounted at secret/ — skipping."
else
  run_bao secrets enable -path=secret kv-v2
  echo "KV v2 secrets engine enabled at secret/."
fi

# Kubernetes auth method at kubernetes/
if run_bao auth list -format=json 2>/dev/null | grep -q '"kubernetes/"'; then
  echo "Kubernetes auth method already enabled — skipping."
else
  run_bao auth enable -path=kubernetes kubernetes
  echo "Kubernetes auth method enabled."
fi

# Configure Kubernetes auth — OpenBao runs in-cluster and auto-discovers the
# CA cert and reviewer token from its own service account.
run_bao write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
echo "Kubernetes auth method configured."

# Policy granting ESO read access to all KV secrets.
echo 'path "secret/data/*"     { capabilities = ["read"] }
path "secret/metadata/*" { capabilities = ["read", "list"] }' \
  | kubectl exec -i -n "$NAMESPACE" "$LEADER" -- \
      env VAULT_TOKEN="$root_token" bao policy write external-secrets -
echo "Policy 'external-secrets' written."

# Role binding the external-secrets service account to that policy.
run_bao write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h
echo "Role 'external-secrets' created."

# Policy granting Helm hook Jobs write access to create secret stubs.
echo 'path "secret/data/*"     { capabilities = ["create", "read", "update"] }
path "secret/metadata/*" { capabilities = ["read"] }' \
  | kubectl exec -i -n "$NAMESPACE" "$LEADER" -- \
      env VAULT_TOKEN="$root_token" bao policy write secret-initializer -
echo "Policy 'secret-initializer' written."

# Role binding the openbao-secret-init service account (any namespace) to that policy.
# Short TTL — this token is only needed for the duration of the Helm hook Job.
run_bao write auth/kubernetes/role/secret-initializer \
  bound_service_account_names=openbao-secret-init \
  bound_service_account_namespaces="*" \
  policies=secret-initializer \
  ttl=5m
echo "Role 'secret-initializer' created."

echo
echo "OpenBao configuration complete."
