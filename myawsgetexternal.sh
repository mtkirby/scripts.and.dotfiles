#!/usr/bin/env bash
# List every public IP in each AWS account, and what it's on, as CSV.
#
# Usage: myawsgetexternal.sh profiles.txt > external.csv
#   profiles.txt: the same list myawsgetregions.sh reads, one AWS CLI profile per
#   line; blank lines and # comments are ignored.
#   JOBS=N sets how many accounts are scanned at once (default 8).
#
# Every enabled region is scanned, not only the ones in regions.csv: an unattached
# Elastic IP or a Lightsail instance can sit in a region with no VPC in use.
# Sources:
#   Network interfaces: public IPv4 (auto-assigned or Elastic), carrier IPs and
#     IPv6 addresses on EC2, NAT gateways, load balancers, ECS tasks, public RDS etc.
#   Elastic IPs that aren't attached to anything (still allocated and billed).
#   Site-to-site VPN tunnel endpoints (the AWS side).
#   Lightsail instances and static IPs, which EC2 doesn't show.
#   Global Accelerator anycast IPs (region "global").
# Not covered: services reached by DNS name with no fixed IPs of their own, such
# as CloudFront, API Gateway, S3, App Runner and public OpenSearch domains. A load
# balancer's IPs can change; its DNS name is the stable address.
#
# Columns: profile,account_id,region,public_ip,ip_type,kind,resource_id,name,private_ip,vpc_id,subnet_id,eni_id,eni_owner_id,security_groups,status
#   ip_type: auto-assigned, elastic, ipv6, carrier, vpn-tunnel, lightsail,
#     lightsail-static or anycast. IPv6 addresses are globally unique, but only
#     reachable from the internet if the subnet routes ::/0 to an internet gateway.
#   kind: what the IP is on: ec2, alb, nlb, clb, nat_gateway, ecs,
#     RDSNetworkInterface etc. "unattached" for an allocated IP on nothing.
#   resource_id: instance id, load balancer, NAT gateway, VPN connection, ARN etc.
#   name: the Name tag of the instance, Elastic IP or interface.
#   eni_owner_id differs from account_id for an interface another account put in a
#     subnet this account shares out (RAM). Both accounts list it.
#   security_groups: group ids, to look up in myawsgetsecgroups.sh output.
#   status is "ok", or the error, e.g. a login failure or a service an SCP denies.
#   Progress and warnings go to stderr, so only the CSV lands in the file.

set -o pipefail
export AWS_PAGER="" AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=10

# One CSV row from the arguments, quoted as needed
csv()
{
    jq -rn '$ARGS.positional | @csv' --args "$@"
}

# A row for an error: profile, account, region, then the message as status
errrow()
{
    csv "$1" "$2" "$3" "" "" "" "" "" "" "" "" "" "" "" "${4//$'\n'/ }"
}

# fetch file what aws-args...: run aws for one_account's profile into file. On
# failure, add an error row to one_account's output and leave {} in the file.
fetch()
{
    local file="$1" what="$2" err
    shift 2
    if ! err="$(aws "$@" --profile "$profile" --output json 2>&1 >"$file")"
    then
        errrow "$profile" "$account" "$region" "$what failed: $err" >>"$out"
        echo '{}' >"$file"
    fi
}

# Write the rows for one account to <dir>/<index>.csv
one_account()
{
    local profile="$3" out="$1/$2.csv" f="$1/$2"
    local account regions region home lsregions

    if ! account="$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>&1)"
    then
        errrow "$profile" "" "" "login failed: $account" >"$out"
        echo "FAIL: $profile: login failed" >&2
        return
    fi

    # Enabled regions only; opt-in regions the account hasn't enabled are left out
    home="$(aws configure get region --profile "$profile")"
    if ! regions="$(aws ec2 describe-regions --profile "$profile" --region "${home:-us-east-1}" \
        --query 'Regions[].RegionName' --output text 2>&1)"
    then
        errrow "$profile" "$account" "" "describe-regions failed: $regions" >"$out"
        echo "FAIL: $profile: can't list regions" >&2
        return
    fi

    : >"$out"
    # Global Accelerator's API is only in us-west-2, wherever its traffic goes
    region=global
    fetch "$f.ga.json" "globalaccelerator list-accelerators" \
        globalaccelerator list-accelerators --region us-west-2
    fetch "$f.gac.json" "globalaccelerator list-custom-routing-accelerators" \
        globalaccelerator list-custom-routing-accelerators --region us-west-2
    jq -rn --arg p "$profile" --arg a "$account" \
        --slurpfile ga "$f.ga.json" --slurpfile gac "$f.gac.json" '
        (($ga[0].Accelerators // [])[], ($gac[0].Accelerators // [])[])
        | . as $x
        | .IpSets[]?.IpAddresses[]?
        | [$p, $a, "global", ., "anycast", "global-accelerator", $x.AcceleratorArn,
           ($x.Name // ""), "", "", "", "", "", "", "ok"]
        | @csv' >>"$out"

    # Lightsail has its own list of regions
    region=""
    if lsregions="$(aws lightsail get-regions --profile "$profile" --region "${home:-us-east-1}" \
        --query 'regions[].name' --output text 2>&1)"
    then
        lsregions=" ${lsregions//$'\t'/ } "
    else
        errrow "$profile" "$account" "" "lightsail get-regions failed: $lsregions" >>"$out"
        lsregions=""
    fi

    for region in $regions
    do
        # Files, not variables: a busy region's interfaces can outgrow a command line
        fetch "$f.enis.json" "describe-network-interfaces" \
            ec2 describe-network-interfaces --region "$region"
        fetch "$f.eips.json" "describe-addresses" ec2 describe-addresses --region "$region"
        fetch "$f.vpns.json" "describe-vpn-connections" \
            ec2 describe-vpn-connections --region "$region"
        # Instance Name tags, only needed when an instance has a public IP
        echo '[]' >"$f.names.json"
        if jq -e 'any(.NetworkInterfaces[]?; .Attachment.InstanceId
            and (any(.PrivateIpAddresses[]?; .Association.PublicIp or .Association.CarrierIp)
                 or (.Ipv6Addresses | length) > 0))' "$f.enis.json" >/dev/null
        then
            # shellcheck disable=SC2016 # the backticks are JMESPath, not shell
            fetch "$f.names.json" "describe-instances" ec2 describe-instances --region "$region" \
                --query 'Reservations[].Instances[].{id: InstanceId, name: Tags[?Key==`Name`] | [0].Value}'
        fi
        echo '{}' >"$f.lsi.json"
        echo '{}' >"$f.lss.json"
        if [[ "$lsregions" == *" $region "* ]]
        then
            fetch "$f.lsi.json" "lightsail get-instances" lightsail get-instances --region "$region"
            fetch "$f.lss.json" "lightsail get-static-ips" lightsail get-static-ips --region "$region"
        fi

        jq -rn --arg p "$profile" --arg a "$account" --arg r "$region" \
            --slurpfile e "$f.enis.json" --slurpfile ad "$f.eips.json" \
            --slurpfile v "$f.vpns.json" --slurpfile i "$f.names.json" \
            --slurpfile li "$f.lsi.json" --slurpfile ls "$f.lss.json" '
            def tag($k): [.[]? | select(.Key == $k) | .Value][0];
            # What an interface belongs to. The description is how AWS labels the
            # interfaces it manages for a service.
            def kind: (.Description // "") as $d
                | if ($d | startswith("ELB app/")) then "alb"
                elif ($d | startswith("ELB net/")) then "nlb"
                elif ($d | startswith("ELB ")) then "clb"
                elif .InterfaceType != "interface" then .InterfaceType
                elif .Attachment.InstanceId then "ec2"
                elif ($d | test("^arn:aws[^:]*:ecs:")) then "ecs"
                elif $d == "" then "other"
                else $d | split(" ")[0]
                end;
            def resource: .Attachment.InstanceId
                // ((.Description // "") | capture("^ELB (?<r>\\S+)").r)
                // ((.Description // "") | capture("(?<r>nat-[0-9a-f]+)").r)
                // (.Description // "");
            def blank: ["", "", "", "", "", ""];

            ($ad[0].Addresses // []) as $eips
            | ($eips | map({key: .PublicIp, value: (.Tags | tag("Name"))}) | from_entries) as $eipname
            | ($i[0] // [] | map({key: .id, value: .name}) | from_entries) as $iname
            | (
                # Interfaces: one row per public address
                (($e[0].NetworkInterfaces // [])[]
                 | . as $n
                 | (kind) as $kind
                 | (resource) as $res
                 | ([.Groups[]?.GroupId] | join(" ")) as $sgs
                 | ((.PrivateIpAddresses[]?
                     | .PrivateIpAddress as $priv
                     | (select(.Association.PublicIp)
                        | {ip: .Association.PublicIp, priv: $priv,
                           type: (if .Association.AllocationId
                                  or (.Association.IpOwnerId // "amazon") != "amazon"
                                  then "elastic" else "auto-assigned" end)}),
                       (select(.Association.CarrierIp)
                        | {ip: .Association.CarrierIp, priv: $priv, type: "carrier"})),
                    (.Ipv6Addresses[]? | {ip: .Ipv6Address, priv: "", type: "ipv6"}))
                 | [$p, $a, $r, .ip, .type, $kind, $res,
                    ($iname[$n.Attachment.InstanceId // ""] // $eipname[.ip]
                     // ($n.TagSet | tag("Name")) // ""),
                    .priv, $n.VpcId, $n.SubnetId, $n.NetworkInterfaceId, $n.OwnerId, $sgs, "ok"]),

                # Elastic IPs on nothing; attached ones are listed with their interface
                ($eips[] | select(.AssociationId | not)
                 | [$p, $a, $r, .PublicIp, "elastic", "unattached", .AllocationId,
                    ((.Tags | tag("Name")) // "")] + blank + ["ok"]),

                # VPN tunnels; ones over Direct Connect use private outside IPs
                (($v[0].VpnConnections // [])[]
                 | select(.State != "deleted"
                          and (.Options.OutsideIpAddressType // "PublicIpv4") == "PublicIpv4")
                 | . as $c
                 | .VgwTelemetry[]?.OutsideIpAddress
                 | [$p, $a, $r, ., "vpn-tunnel", "vpn", $c.VpnConnectionId,
                    (($c.Tags | tag("Name")) // "")] + blank + ["ok"]),

                # Lightsail instances, and static IPs on nothing
                (($li[0].instances // [])[]
                 | . as $x
                 | ((.publicIpAddress // empty
                     | {ip: ., type: (if $x.isStaticIp then "lightsail-static" else "lightsail" end)}),
                    (.ipv6Addresses[]? | {ip: ., type: "ipv6"}))
                 | [$p, $a, $r, .ip, .type, "lightsail", $x.arn, $x.name,
                    ($x.privateIpAddress // ""), "", "", "", "", "", "ok"]),
                (($ls[0].staticIps // [])[] | select(.isAttached | not)
                 | [$p, $a, $r, .ipAddress, "lightsail-static", "unattached", .arn, .name]
                   + blank + ["ok"])
            )
            | @csv' >>"$out"
    done
    rm -f "$f".*.json
    echo "done: $profile ($account)" >&2
}

if [[ "$1" == --one ]]
then
    one_account "$2" "$3" "$4"
    exit 0
fi

if [[ ! -r "$1" ]]
then
    echo "Usage: ${0##*/} profiles.txt > external.csv" >&2
    exit 1
fi
for cmd in aws jq
do
    if ! command -v "$cmd" >/dev/null 2>&1
    then
        echo "FAIL: $cmd not found" >&2
        exit 1
    fi
done

profiles=()
while IFS= read -r line || [[ -n "$line" ]]
do
    line="${line%$'\r'}"
    line="${line%%#*}"
    # trim leading and trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && profiles+=("$line")
done <"$1"
if (( ${#profiles[@]} == 0 ))
then
    echo "FAIL: no profiles in $1" >&2
    exit 1
fi

# All the SSO profiles share one login, so check it once before starting
if ! aws sts get-caller-identity --profile "${profiles[0]}" >/dev/null 2>&1
then
    if command -v aws-sso-util >/dev/null 2>&1
    then
        echo "SSO login needed; running aws-sso-util login" >&2
        aws-sso-util login >&2 || exit 1
    else
        echo "WARN: ${profiles[0]} can't log in; run aws-sso-util login first" >&2
    fi
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

echo "Scanning ${#profiles[@]} accounts, ${JOBS:-8} at a time" >&2
for i in "${!profiles[@]}"
do
    printf '%s %s\n' "$i" "${profiles[i]}"
done | xargs -n 2 -P "${JOBS:-8}" bash "$0" --one "$tmp"

csv profile account_id region public_ip ip_type kind resource_id name private_ip \
    vpc_id subnet_id eni_id eni_owner_id security_groups status
for i in "${!profiles[@]}"
do
    cat "$tmp/$i.csv" 2>/dev/null
done
