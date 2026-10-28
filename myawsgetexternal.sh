#!/usr/bin/env bash
# List every public IP in use in each AWS account, and what it's on, as CSV.
#
# Usage: myawsgetexternal.sh profiles.txt > external.csv
#   profiles.txt: the same list myawsgetregions.sh reads, one AWS CLI profile per
#   line; blank lines and # comments are ignored.
#   JOBS=N sets how many accounts are scanned at once (default 8).
#
# Only one call per region, ec2 describe-network-interfaces, so it needs nothing
# beyond ec2:DescribeRegions and ec2:DescribeNetworkInterfaces. Everything in a VPC
# with a public IP has a network interface: EC2, load balancers, NAT gateways, ECS
# tasks, public RDS etc., including any Elastic IPs attached to them.
# Not covered: Elastic IPs attached to nothing, Lightsail, Global Accelerator, VPN
# endpoints, and services reached by DNS name (CloudFront, API Gateway, S3).
#
# Columns: profile,account_id,region,public_ip,ip_type,kind,resource_id,private_ip,vpc_id,subnet_id,eni_id,eni_owner_id,security_groups
#   ip_type: auto-assigned, elastic, ipv6 or carrier. IPv6 addresses are globally
#     unique, but only reachable from the internet if the subnet routes ::/0 to an
#     internet gateway.
#   kind: ec2, alb, nlb, clb, nat_gateway, ecs, RDSNetworkInterface etc.
#   resource_id: instance id, load balancer, NAT gateway, else the description.
#   eni_owner_id differs from account_id for an interface another account put in a
#     subnet this account shares out (RAM). Both accounts list it.
#   security_groups: group ids, to look up in myawsgetsecgroups.sh output.
# Only IPs land in the CSV. Accounts that can't log in and regions that can't be
# read (e.g. an SCP denies them) are reported on stderr.

set -o pipefail
export AWS_PAGER="" AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=10

# One CSV row from the arguments, quoted as needed
csv()
{
    jq -rn '$ARGS.positional | @csv' --args "$@"
}

# Write the rows for one account to <dir>/<index>.csv
one_account()
{
    local profile="$3" out="$1/$2.csv" enis="$1/$2.enis.json"
    local account regions region home err failed="" firsterr=""

    : >"$out"
    if ! account="$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>&1)"
    then
        echo "FAIL: $profile: login failed: ${account//$'\n'/ }" >&2
        return
    fi

    # Enabled regions only; opt-in regions the account hasn't enabled are left out
    home="$(aws configure get region --profile "$profile")"
    if ! regions="$(aws ec2 describe-regions --profile "$profile" --region "${home:-us-east-1}" \
        --query 'Regions[].RegionName' --output text 2>&1)"
    then
        echo "FAIL: $profile ($account): can't list regions: ${regions//$'\n'/ }" >&2
        return
    fi

    for region in $regions
    do
        # A file, not a variable: a busy region's interfaces can outgrow a command line
        if ! err="$(aws ec2 describe-network-interfaces --profile "$profile" --region "$region" \
            --output json 2>&1 >"$enis")"
        then
            failed+=" $region"
            [[ -z "$firsterr" ]] && firsterr="${err//$'\n'/ }"
            continue
        fi
        jq -r --arg p "$profile" --arg a "$account" --arg r "$region" '
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

            .NetworkInterfaces[]?
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
            | [$p, $a, $r, .ip, .type, $kind, $res, .priv,
               $n.VpcId, $n.SubnetId, $n.NetworkInterfaceId, $n.OwnerId, $sgs]
            | @csv' "$enis" >>"$out"
    done
    rm -f "$enis"
    if [[ -n "$failed" ]]
    then
        echo "WARN: $profile ($account): couldn't read$failed: $firsterr" >&2
    fi
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

csv profile account_id region public_ip ip_type kind resource_id private_ip \
    vpc_id subnet_id eni_id eni_owner_id security_groups
for i in "${!profiles[@]}"
do
    cat "$tmp/$i.csv" 2>/dev/null
done
