#!/usr/bin/env bash
## Reproduce the stale shared subscription members issue on a given EMQX version,
## apply this hot patch to the running node, and verify that it took effect.
##
## Usage: ./reproduce-patch-verify.sh <emqx-version>     e.g. 6.3.3 or 5.10.5
##
## Environment:
##   IMAGE=<image>   Docker image to test (default: emqx/emqx-enterprise:<emqx-version>).
##   WAIT_PURGE=1    Wait for the periodic purge (about 15 to 20 minutes) instead of
##                   triggering it.
##   KEEP=1          Leave the containers running at the end.
##
## The test cluster has one core node and one replicant node, with the default
## routing schema (v3). A shared subscription has one member on each node. The
## replicant is killed, so it cannot remove its own member. The script then shows:
##   1. the member of the dead node stays in the shared subscription table;
##   2. half of the messages published to the group are lost;
## loads the patched modules into the core node, starts the router helper
## (routing schema v3 only), and checks that:
##   3. the patched modules are loaded from the patches directory;
##   4. no message is lost;
##   5. the router helper finds the dead node and its purge removes the member.

set -euo pipefail

VSN="${1:-}"
if [ -z "$VSN" ]; then
    sed -n '2,25p' "$0" | sed 's/^## \{0,1\}//'
    exit 2
fi
VSN="${VSN#e}"
MINOR="$(echo "$VSN" | cut -d. -f1,2)"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$HERE/$MINOR"
if [ ! -d "$PATCH_DIR" ]; then
    echo "No patch for EMQX $MINOR in $HERE" >&2
    exit 2
fi

IMAGE="${IMAGE:-emqx/emqx-enterprise:$VSN}"
PROJECT="hp-ssr-$(echo "$VSN" | tr -c 'a-z0-9\n' '-')"
NET="${PROJECT}_hp"
CORE="${PROJECT}-core1"
REPLICANT="${PROJECT}-replicant1"
SUB_CORE="${PROJECT}-sub-core1"
SUB_REPLICANT="${PROJECT}-sub-replicant1"
CORE_NODE="emqx@core1.hp.emqx.io"
REPLICANT_NODE="emqx@replicant1.hp.emqx.io"
MQTTX_IMAGE="emqx/mqttx-cli:latest"
MODULES=(emqx_shared_sub emqx_router_helper emqx_router_sup)
WORK="$(mktemp -d)"
FAILED=0

log() { echo "=== $*"; }
pass() { echo "    OK: $*"; }
fail() { echo "    FAILED: $*"; FAILED=1; }

cleanup() {
    if [ "${KEEP:-0}" = "1" ]; then
        echo "Containers kept. Remove them with:"
        echo "  docker rm -f $SUB_CORE $SUB_REPLICANT; docker compose -p $PROJECT -f $WORK/compose.yaml down -v"
        return
    fi
    docker rm -f "$SUB_CORE" "$SUB_REPLICANT" >/dev/null 2>&1 || true
    docker compose -p "$PROJECT" -f "$WORK/compose.yaml" down -v >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

## emqx eval on the core node
ev() {
    docker exec "$CORE" /opt/emqx/bin/emqx eval "$1"
}

## wait_for <timeout-seconds> <description> <command...>
wait_for() {
    local timeout="$1" what="$2"
    shift 2
    local i=0
    until "$@" >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge "$timeout" ]; then
            echo "Timed out waiting for: $what" >&2
            return 1
        fi
        sleep 1
    done
}

is_true() { [ "$(ev "$1" | tr -d '[:space:]')" = "true" ]; }

received() {
    docker logs "$SUB_CORE" 2>&1 | grep -c '"cmd": "publish"' || true
}

## publish 10 QoS 1 messages from one process on the core node, then count how many
## reach the subscriber on the core node
publish_10() {
    local before after
    before="$(received)"
    ev '[emqx:publish(emqx_message:make(<<"hp">>, 1, <<"hp/t">>, integer_to_binary(I))) || I <- lists:seq(1, 10)], ok.' >/dev/null
    sleep 3
    after="$(received)"
    echo $((after - before))
}

has_stale_member() {
    is_true "lists:member('$REPLICANT_NODE', [node(P) || {_, _, _, P} <- ets:tab2list(emqx_shared_subscription)])."
}

no_stale_member() { ! has_stale_member; }

cat >"$WORK/compose.yaml" <<EOF
x-emqx: &emqx
  image: $IMAGE
  environment: &env
    EMQX_NODE__COOKIE: hotpatch
    EMQX_LICENSE__KEY: evaluation
    EMQX_NODE__DIST_NET_TICKTIME: 10s
    EMQX_CLUSTER__DISCOVERY_STRATEGY: static
    EMQX_CLUSTER__STATIC__SEEDS: '[$CORE_NODE]'
    EMQX_BROKER__SHARED_SUBSCRIPTION_STRATEGY: round_robin
services:
  core1:
    <<: *emqx
    container_name: $CORE
    environment:
      <<: *env
      EMQX_NODE__NAME: $CORE_NODE
    networks:
      hp:
        aliases: [core1.hp.emqx.io]
  replicant1:
    <<: *emqx
    container_name: $REPLICANT
    environment:
      <<: *env
      EMQX_NODE__NAME: $REPLICANT_NODE
      EMQX_NODE__ROLE: replicant
    networks:
      hp:
        aliases: [replicant1.hp.emqx.io]
networks:
  hp: {}
EOF

log "Starting a core and a replicant node with $IMAGE"
docker compose -p "$PROJECT" -f "$WORK/compose.yaml" up -d --quiet-pull >/dev/null
wait_for 120 "core node is up" docker exec "$CORE" /opt/emqx/bin/emqx ctl status
wait_for 120 "replicant node is up" docker exec "$REPLICANT" /opt/emqx/bin/emqx ctl status
wait_for 120 "replicant joined the cluster" is_true "lists:member('$REPLICANT_NODE', mria:running_nodes())."
SCHEMA="$(ev 'emqx_router:get_schema_vsn().' | tr -d '[:space:]')"
echo "    EMQX $VSN, routing schema $SCHEMA, router helper process: $(ev 'whereis(emqx_router_helper).' | tr -d '[:space:]')"

log "Subscribing one member of \$share/g/hp/t on each node"
for pair in "$SUB_CORE:core1.hp.emqx.io" "$SUB_REPLICANT:replicant1.hp.emqx.io"; do
    docker run -d --name "${pair%%:*}" --network "$NET" "$MQTTX_IMAGE" \
        mqttx sub -h "${pair#*:}" -t '$share/g/hp/t' -q 1 --output-mode clean >/dev/null
done
wait_for 60 "both members are subscribed" is_true \
    "length([P || {_, <<\"g\">>, <<\"hp/t\">>, P} <- ets:tab2list(emqx_shared_subscription)]) =:= 2."

log "Killing the replicant node, so it cannot remove its own member"
docker kill "$REPLICANT" >/dev/null
docker rm -f "$SUB_REPLICANT" >/dev/null
wait_for 120 "the core node sees the replicant down" is_true \
    "not lists:member('$REPLICANT_NODE', mria:running_nodes())."

log "Reproducing (unpatched)"
if has_stale_member; then
    pass "REPRODUCED: the member of the dead replicant is still in the shared subscription table"
else
    fail "the member of the dead replicant is already gone; the issue did not reproduce"
fi
N="$(publish_10)"
if [ "$N" -lt 10 ]; then
    pass "REPRODUCED: $N of 10 messages reached the live member; $((10 - N)) were lost"
else
    fail "all 10 messages reached the live member; the issue did not reproduce"
fi

log "Patching the core node with $PATCH_DIR"
(cd "$PATCH_DIR" && sha256sum -c --quiet ./*.sha256)
for m in "${MODULES[@]}"; do
    docker cp -q "$PATCH_DIR/$m.beam" "$CORE:/opt/emqx/data/patches/$m.beam"
done
docker exec -u 0 "$CORE" sh -c 'chown emqx:emqx /opt/emqx/data/patches/*.beam'
ev '
Mods = [emqx_shared_sub, emqx_router_helper, emqx_router_sup],
Loaded = [c:l(M) || M <- Mods],
true = lists:all(fun(M) -> string:find(code:which(M), "/patches/") =/= nomatch end, Mods),
Helper =
    case emqx_router:get_schema_vsn() of
        v3 ->
            supervisor:start_child(emqx_router_sup, #{
                id => helper,
                start => {emqx_router_helper, start_link, []},
                restart => permanent,
                shutdown => 5000,
                type => worker,
                modules => [emqx_router_helper]
            });
        v2 ->
            already_running
    end,
{Loaded, Helper}.'

log "Verifying"
for m in "${MODULES[@]}"; do
    if is_true "{ok, {_, MD5}} = beam_lib:md5(\"/opt/emqx/data/patches/$m.beam\"), $m:module_info(md5) =:= MD5."; then
        pass "$m is loaded from the patches directory"
    else
        fail "$m is not the patched module"
    fi
done
if is_true "is_pid(whereis(emqx_router_helper))."; then
    pass "the router helper is running"
else
    fail "the router helper is not running"
fi
N="$(publish_10)"
if [ "$N" -eq 10 ]; then
    pass "VERIFIED: 10 of 10 messages reached the live member"
else
    fail "$N of 10 messages reached the live member"
fi
if wait_for 300 "the router helper marks the replicant down" is_true \
    "[S || {ns, '$REPLICANT_NODE', S, _, _} <- ets:tab2list(emqx_router_helper)] =:= [down]."; then
    pass "the router helper found the dead replicant and marked it down"
else
    fail "the router helper did not mark the dead replicant down"
fi
if [ "${WAIT_PURGE:-0}" = "1" ]; then
    echo "    Waiting for the periodic purge, up to 25 minutes"
    PURGE_TIMEOUT=1500
else
    echo "    Triggering the purge now (emqx_router_helper:schedule_force_purge/0) instead of waiting 15 minutes"
    ev 'emqx_router_helper:schedule_force_purge().' >/dev/null
    PURGE_TIMEOUT=60
fi
if wait_for "$PURGE_TIMEOUT" "the purge removes the member" no_stale_member; then
    pass "VERIFIED: the purge removed the member of the dead replicant"
else
    fail "the member of the dead replicant is still in the shared subscription table"
fi

if [ "$FAILED" = "0" ]; then
    log "PASS: EMQX $VSN reproduced the issue, and the patch fixed it"
else
    log "FAIL: see the FAILED lines above"
fi
exit "$FAILED"
